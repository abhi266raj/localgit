import Foundation

public struct ExecutionResult {
    public let command: String
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let combinedOutput: String

    public var isSuccess: Bool {
        return exitCode == 0
    }

    public init(
        command: String,
        exitCode: Int32,
        stdout: String,
        stderr: String,
        combinedOutput: String
    ) {
        self.command = command
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.combinedOutput = combinedOutput
    }
}

public enum CommandExecutor {
    public static func isGitCommandSafe(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return false
        }

        let forbidden = ["rm -rf /", "mkfs", "dd if=", ":(){ :|:& };:"]
        for f in forbidden {
            if trimmed.contains(f) {
                return false
            }
        }
        return true
    }

    public static func execute(command: String, cwd: String? = nil) -> ExecutionResult {
        guard isGitCommandSafe(command) else {
            return ExecutionResult(
                command: command,
                exitCode: -1,
                stdout: "",
                stderr: "Refusing to execute potentially unsafe command: \(command)",
                combinedOutput: "Unsafe command rejected."
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

            let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            var combinedParts: [String] = []
            if !outStr.isEmpty { combinedParts.append(outStr) }
            if !errStr.isEmpty { combinedParts.append(errStr) }
            let combined = combinedParts.joined(separator: "\n")

            return ExecutionResult(
                command: command,
                exitCode: process.terminationStatus,
                stdout: outStr,
                stderr: errStr,
                combinedOutput: combined
            )
        } catch {
            return ExecutionResult(
                command: command,
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription,
                combinedOutput: error.localizedDescription
            )
        }
    }
}
