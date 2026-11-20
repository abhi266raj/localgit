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
    func synthesizeOutput(task: String, executedCommand: String, exitCode: Int32, rawTerminalOutput: String) async throws -> String
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
    1. The 'thought' field MUST explain your reasoning and diagnosis.
    2. The 'command' field MUST contain the exact command to run in the terminal (e.g., 'git add . && git commit -m "feat: add login"').
    3. Chain multiple commands with '&&' if multiple steps are needed.
    4. Every command must invoke 'git' or safe shell utilities needed for git operations.
    5. If the task is already satisfied or cannot be done, explain in 'thought' and 'explanation' and set command to '' (empty string).
    6. For error recovery: diagnose the root cause carefully (e.g. untracked conflicts, detached HEAD, missing upstream, existing branch) and generate the precise fix.
    """

    public static let outputSynthesisInstructions = """
    You are an assistant reporting Git command execution results to the user.
    Given the user's original task and the raw terminal output from the executed command:
    Synthesize a clean, user-friendly explanation of what was done and the result.
    Keep it concise (1-2 sentences). Do not use markdown code fences.
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
            thought: "Analyzing repository state and generating command",
            command: cmd,
            explanation: "Extracted git command directly from model response",
            rawResponse: rawText
        )
    }

    private func executeFM(prompt: String, instructions: String, schema: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)

        var args = [
            "respond",
            "--no-stream",
            "-i", instructions
        ]
        if let s = schema {
            args.append(contentsOf: ["--schema", s])
        }
        args.append(prompt)

        process.arguments = args

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
        let schema = try ensureSchemaPath()
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

        Provide the exact git command to execute. Include your reasoning in the 'thought' field.
        """)

        let prompt = sections.joined(separator: "\n\n")
        let raw = try executeFM(prompt: prompt, instructions: AppleFMClient.defaultInstructions, schema: schema)
        return parseResponse(raw)
    }

    public func planRecovery(
        task: String,
        failedCommand: String,
        exitCode: Int32,
        output: String,
        gitContext: String
    ) async throws -> GitPlan {
        let schema = try ensureSchemaPath()
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

        Diagnose the exact root cause of this failure in 'thought' and provide the corrected git command in 'command' to fix the issue and achieve the goal.
        """
        let raw = try executeFM(prompt: prompt, instructions: AppleFMClient.defaultInstructions, schema: schema)
        return parseResponse(raw)
    }

    public func synthesizeOutput(
        task: String,
        executedCommand: String,
        exitCode: Int32,
        rawTerminalOutput: String
    ) async throws -> String {
        let prompt = """
        User Goal:
        \(task)

        Executed Command:
        \(executedCommand) (exit code \(exitCode))

        Terminal Output:
        \(rawTerminalOutput.isEmpty ? "(Command completed successfully with empty output)" : rawTerminalOutput)

        Explain clearly what was done and the result to show to the user.
        """
        do {
            let response = try executeFM(prompt: prompt, instructions: AppleFMClient.outputSynthesisInstructions)
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        } catch {
            // Fallback to formatted terminal output if synthesis fails
        }

        if !rawTerminalOutput.isEmpty {
            return rawTerminalOutput
        }
        return "Command executed successfully."
    }
}
