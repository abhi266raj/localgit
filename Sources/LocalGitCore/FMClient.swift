import Foundation

public struct GitPlan: Codable, Equatable {
    public let thought: String
    public let command: String
    public let explanation: String
    public var rawResponse: String? = nil

    public init(thought: String, command: String, explanation: String, rawResponse: String? = nil) {
        self.thought = thought
        self.command = command
        self.explanation = explanation
        self.rawResponse = rawResponse
    }
}

public protocol FMClientProtocol {
    func isAvailable() -> Bool
    func planAction(task: String, gitContext: String, sessionHistory: String?) async throws -> GitPlan
    func planRecovery(task: String, failedCommand: String, exitCode: Int32, output: String, gitContext: String) async throws -> GitPlan
}

public extension FMClientProtocol {
    func planAction(task: String, gitContext: String) async throws -> GitPlan {
        return try await planAction(task: task, gitContext: gitContext, sessionHistory: nil)
    }
}

public class AppleFMClient: FMClientProtocol {
    public let binaryPath: String
    private var schemaPath: String?

    public static let defaultInstructions = """
    You are an expert autonomous Git engineering agent.
    Your mission is to translate user goals or errors into exact, correct Git commands.

    Rules:
    1. The 'command' field MUST contain the exact command to run in the terminal (e.g., 'git add . && git commit -m "feat: add login"').
    2. Chain multiple commands with '&&' if multiple steps are needed.
    3. Every command must invoke 'git' or safe shell utilities needed for git operations.
    4. If the task is already satisfied or cannot be done, explain in 'thought' and 'explanation' and set command to '' (empty string).
    5. For error recovery: diagnose the root cause carefully (e.g. untracked conflicts, detached HEAD, missing upstream, existing branch) and generate the precise fix.
    """

    public init(binaryPath: String = "/usr/bin/fm") {
        self.binaryPath = binaryPath
    }

    public func isAvailable() -> Bool {
        guard FileManager.default.fileExists(atPath: binaryPath) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["available"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8) ?? ""
            return process.terminationStatus == 0 && str.contains("System model available")
        } catch {
            return false
        }
    }

    private func ensureSchemaPath() throws -> String {
        if let existing = schemaPath, FileManager.default.fileExists(atPath: existing) {
            return existing
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("localgit")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("git_plan_schema.json")

        let schemaDict: [String: Any] = [
            "title": "GitPlan",
            "type": "object",
            "required": ["thought", "command", "explanation"],
            "additionalProperties": false,
            "properties": [
                "thought": [
                    "type": "string",
                    "description": "Analysis of the repository state and strategy"
                ],
                "command": [
                    "type": "string",
                    "description": "Exact git command(s) to execute in shell"
                ],
                "explanation": [
                    "type": "string",
                    "description": "User-friendly explanation of what the command does"
                ]
            ],
            "x-order": ["thought", "command", "explanation"]
        ]

        let data = try JSONSerialization.data(withJSONObject: schemaDict, options: [.prettyPrinted])
        try data.write(to: fileURL)

        self.schemaPath = fileURL.path
        return fileURL.path
    }

    public func parseResponse(_ rawText: String) -> GitPlan {
        var cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try extracting JSON from ```json ... ``` code fence
        if let blockRegex = try? NSRegularExpression(pattern: "```(?:json)?\\s*(\\{.*?\\})\\s*```", options: [.dotMatchesLineSeparators]) {
            let nsStr = cleaned as NSString
            if let match = blockRegex.firstMatch(in: cleaned, range: NSRange(location: 0, length: nsStr.length)) {
                cleaned = nsStr.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let nakedRegex = try? NSRegularExpression(pattern: "(\\{.*\\})", options: [.dotMatchesLineSeparators]) {
            let nsStr = cleaned as NSString
            if let match = nakedRegex.firstMatch(in: cleaned, range: NSRange(location: 0, length: nsStr.length)) {
                cleaned = nsStr.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let data = cleaned.data(using: .utf8),
           let plan = try? JSONDecoder().decode(GitPlan.self, from: data) {
            return GitPlan(
                thought: plan.thought.trimmingCharacters(in: .whitespacesAndNewlines),
                command: plan.command.trimmingCharacters(in: .whitespacesAndNewlines),
                explanation: plan.explanation.trimmingCharacters(in: .whitespacesAndNewlines),
                rawResponse: rawText
            )
        }

        // Fallback: search for git command in text
        let lines = rawText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let gitLines = lines.filter { $0.hasPrefix("git ") || $0.contains("git ") }
        let cmd = gitLines.first ?? ""

        return GitPlan(
            thought: "Fallback command extraction",
            command: cmd,
            explanation: "Extracted git command directly from model response",
            rawResponse: rawText
        )
    }

    private func executeFM(prompt: String) throws -> String {
        let schema = try ensureSchemaPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "respond",
            "--no-stream",
            "--schema", schema,
            "-i", AppleFMClient.defaultInstructions,
            prompt
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            throw NSError(domain: "AppleFMClient", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "fm command failed: \(errStr)"
            ])
        }

        return outStr
    }

    public func planAction(task: String, gitContext: String, sessionHistory: String? = nil) async throws -> GitPlan {
        var sections: [String] = []

        if let history = sessionHistory, !history.isEmpty {
            sections.append("""
            Previous Session History:
            \(history)
            """)
        }

        sections.append("""
        Repository State:
        \(gitContext)
        """)

        sections.append("""
        User Task:
        \(task)

        Provide the exact git command to execute.
        """)

        let prompt = sections.joined(separator: "\n\n")
        let raw = try executeFM(prompt: prompt)
        return parseResponse(raw)
    }

    public func planRecovery(
        task: String,
        failedCommand: String,
        exitCode: Int32,
        output: String,
        gitContext: String
    ) async throws -> GitPlan {
        let prompt = """
        An error occurred while attempting to satisfy the user goal.

        User Goal:
        \(task)

        Previous Command Attempted:
        \(failedCommand)

        Exit Code:
        \(exitCode)

        Terminal Output / Error:
        \(output.isEmpty ? "(no output)" : output)

        Updated Repository State:
        \(gitContext)

        Diagnose the exact root cause of this failure and provide the corrected git command to fix the issue and achieve the goal.
        """
        let raw = try executeFM(prompt: prompt)
        return parseResponse(raw)
    }
}
