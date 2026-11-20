import Foundation

/// Encapsulates the complete outcome of executing a shell command.
///
/// Contains the command string that was dispatched, the kernel exit code,
/// individual stdout and stderr buffers, and a merged combined string used
/// for logging and feeding back to the LLM for diagnosis.
public struct ExecutionResult: Equatable {
    /// The exact shell command string that was executed.
    public let command: String

    /// The exit status code returned by the process (0 indicates success).
    public let exitCode: Int32

    /// Captured text from the standard output stream (`stdout`).
    public let stdout: String

    /// Captured text from the standard error stream (`stderr`).
    public let stderr: String

    /// Combined text of stdout and stderr in chronological order.
    public let combinedOutput: String

    /// Convenience flag indicating whether the command succeeded without error (`exitCode == 0`).
    public var isSuccess: Bool {
        return exitCode == 0
    }

    /// Memberwise initializer.
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

/// Dispatches shell commands safely using `Foundation.Process`, capturing real-time stream output.
public enum CommandExecutor {

    /// List of potentially destructive system command substrings that should never be executed autonomously.
    public static let forbiddenTokens: [String] = [
        "rm -rf /",
        "mkfs",
        "dd if=",
        ":(){ :|:& };:"
    ]

    /// Performs validation to ensure generated commands do not attempt destructive system operations.
    ///
    /// - Parameter command: The proposed command string to inspect.
    /// - Returns: `true` if the command passes safety checks; otherwise `false`.
    public static func isGitCommandSafe(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        for token in forbiddenTokens {
            if trimmed.contains(token) {
                return false
            }
        }
        return true
    }

    /// Reads all available data from a `Pipe`'s file handle and decodes it into a UTF-8 string.
    ///
    /// - Parameter pipe: The pipe connected to the subprocess stream.
    /// - Returns: Trimmed string representation of the pipe buffer.
    public static func readStreamOutput(from pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Configures and launches a shell subprocess executing the given command string.
    ///
    /// - Parameters:
    ///   - command: The shell command to run.
    ///   - cwd: Optional directory path in which the process should run.
    ///   - outPipe: Output pipe to capture `stdout`.
    ///   - errPipe: Output pipe to capture `stderr`.
    /// - Returns: The spawned and completed `Process` instance.
    private static func spawnProcess(
        command: String,
        cwd: String?,
        outPipe: Pipe,
        errPipe: Pipe
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()
        return process
    }

    /// Executes a command in the user's shell and captures all resulting output streams.
    ///
    /// The execution pipeline:
    /// 1. Validates the command using `isGitCommandSafe`.
    /// 2. Spawns `/bin/zsh -c "<command>"` using `Foundation.Process`.
    /// 3. Reads stdout and stderr through dedicated Unix pipes.
    /// 4. Assembles an `ExecutionResult` containing the exit code and outputs.
    ///
    /// - Parameters:
    ///   - command: The command string to execute.
    ///   - cwd: Optional target repository directory.
    /// - Returns: A populated `ExecutionResult` structure.
    public static func execute(command: String, cwd: String? = nil) -> ExecutionResult {
        // Step 1: Safety validation
        guard isGitCommandSafe(command) else {
            return ExecutionResult(
                command: command,
                exitCode: -1,
                stdout: "",
                stderr: "Refusing to execute potentially unsafe command: \(command)",
                combinedOutput: "Unsafe command rejected."
            )
        }

        // Step 2: Setup streams
        let outPipe = Pipe()
        let errPipe = Pipe()

        // Step 3: Run process
        do {
            let process = try spawnProcess(command: command, cwd: cwd, outPipe: outPipe, errPipe: errPipe)

            // Step 4: Extract output strings
            let stdout = readStreamOutput(from: outPipe)
            let stderr = readStreamOutput(from: errPipe)

            var combinedParts: [String] = []
            if !stdout.isEmpty { combinedParts.append(stdout) }
            if !stderr.isEmpty { combinedParts.append(stderr) }
            let combined = combinedParts.joined(separator: "\n")

            return ExecutionResult(
                command: command,
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr,
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
