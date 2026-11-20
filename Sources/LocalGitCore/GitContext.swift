import Foundation

/// Represents an immutable snapshot of a Git repository's current state.
///
/// This context is passed directly to the local Apple Foundation Model before any action
/// is planned. By providing the model with real-time repository state (branch, working tree changes,
/// recent commits, and remotes), we ground the model's reasoning and prevent hallucinations.
public struct GitState: Equatable {
    /// Indicates whether the inspected directory is part of an active Git work tree.
    public let isRepo: Bool

    /// The name of the active branch (e.g. "main", "feature/login") or nil if detached/uninitialized.
    public let branch: String?

    /// Short status summary of modified, added, and untracked files (`git status --short --branch`).
    public let statusSummary: String

    /// One-line log of recent commits (`git log -n 3 --oneline`).
    public let recentLogs: String

    /// Configured remote repositories (`git remote -v`).
    public let remotes: String

    /// Error message captured if the Git inspection failed.
    public let error: String?

    /// Memberwise initializer for `GitState`.
    public init(
        isRepo: Bool,
        branch: String?,
        statusSummary: String,
        recentLogs: String,
        remotes: String,
        error: String? = nil
    ) {
        self.isRepo = isRepo
        self.branch = branch
        self.statusSummary = statusSummary
        self.recentLogs = recentLogs
        self.remotes = remotes
        self.error = error
    }

    /// Serializes the Git repository snapshot into a structured text prompt for the LLM.
    ///
    /// The formatted string presents the branch, status summary, commit log, and remotes
    /// in a clear key-value format that the Apple Foundation Model can easily parse.
    ///
    /// - Returns: A multiline string describing the repository state.
    public func toPromptContext() -> String {
        guard isRepo else {
            return "Current Directory: NOT inside a git repository."
        }

        var lines = [
            "Git Repository Context:",
            "- Current Branch: \(branch ?? "None (detached HEAD or uninitialized)")",
            "- Status Summary:\n\(statusSummary.isEmpty ? "  Clean working tree" : statusSummary)"
        ]

        if !recentLogs.isEmpty {
            lines.append("- Recent Commits:\n\(recentLogs)")
        } else {
            lines.append("- Recent Commits: No commits yet.")
        }

        if !remotes.isEmpty {
            lines.append("- Configured Remotes:\n\(remotes)")
        }

        return lines.joined(separator: "\n")
    }
}

/// Utility for inspecting the local filesystem and gathering live Git repository metadata.
public enum GitContextInspector {

    /// Spawns the system `/usr/bin/git` binary with specified arguments and captures standard streams.
    ///
    /// - Parameters:
    ///   - args: Command-line arguments passed directly to the `git` executable (e.g. `["status", "--short"]`).
    ///   - cwd: Optional target directory path where the command should execute.
    /// - Returns: A tuple containing the process exit code, trimmed standard output, and trimmed standard error.
    public static func runGit(args: [String], cwd: String?) -> (exitCode: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args

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

            return (process.terminationStatus, outStr, errStr)
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }

    /// Verifies whether the directory is an active Git work tree via `git rev-parse --is-inside-work-tree`.
    public static func queryIsInsideWorkTree(cwd: String?) -> (isRepo: Bool, error: String?) {
        let result = runGit(args: ["rev-parse", "--is-inside-work-tree"], cwd: cwd)
        let isRepo = (result.exitCode == 0 && result.output == "true")
        return (isRepo, isRepo ? nil : result.error)
    }

    /// Queries the name of the currently checked-out branch.
    ///
    /// Attempts `git branch --show-current` first. If detached or in an unborn state,
    /// falls back to `git rev-parse --abbrev-ref HEAD`.
    public static func queryCurrentBranch(cwd: String?) -> String? {
        let branchCheck = runGit(args: ["branch", "--show-current"], cwd: cwd)
        if !branchCheck.output.isEmpty {
            return branchCheck.output
        }

        let headCheck = runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd)
        if !headCheck.output.isEmpty && headCheck.output != "HEAD" {
            return headCheck.output
        }

        return nil
    }

    /// Queries a concise overview of working directory changes via `git status --short --branch`.
    public static func queryStatusSummary(cwd: String?) -> String {
        return runGit(args: ["status", "--short", "--branch"], cwd: cwd).output
    }

    /// Queries the last few commits in one-line format via `git log -n <limit> --oneline`.
    public static func queryRecentLogs(limit: Int = 3, cwd: String?) -> String {
        return runGit(args: ["log", "-n", "\(limit)", "--oneline"], cwd: cwd).output
    }

    /// Queries all configured remote repository URLs via `git remote -v`.
    public static func queryRemotes(cwd: String?) -> String {
        return runGit(args: ["remote", "-v"], cwd: cwd).output
    }

    /// Gathers full repository context for the specified directory by executing targeted git queries.
    ///
    /// - Parameter cwd: The repository directory to inspect (defaults to current process directory).
    /// - Returns: A complete `GitState` object containing all metadata required by the agent.
    public static func getGitState(cwd: String? = nil) -> GitState {
        let workTreeCheck = queryIsInsideWorkTree(cwd: cwd)
        guard workTreeCheck.isRepo else {
            return GitState(
                isRepo: false,
                branch: nil,
                statusSummary: "",
                recentLogs: "",
                remotes: "",
                error: workTreeCheck.error
            )
        }

        let branch = queryCurrentBranch(cwd: cwd)
        let status = queryStatusSummary(cwd: cwd)
        let logs = queryRecentLogs(limit: 3, cwd: cwd)
        let remotes = queryRemotes(cwd: cwd)

        return GitState(
            isRepo: true,
            branch: branch,
            statusSummary: status,
            recentLogs: logs,
            remotes: remotes
        )
    }
}
