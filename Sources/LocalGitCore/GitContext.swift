import Foundation

public struct GitState {
    public let isRepo: Bool
    public let branch: String?
    public let statusSummary: String
    public let recentLogs: String
    public let remotes: String
    public let error: String?

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

public enum GitContextInspector {
    private static func runGit(args: [String], cwd: String?) -> (exitCode: Int32, output: String, error: String) {
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

    public static func getGitState(cwd: String? = nil) -> GitState {
        let check = runGit(args: ["rev-parse", "--is-inside-work-tree"], cwd: cwd)
        if check.exitCode != 0 {
            return GitState(
                isRepo: false,
                branch: nil,
                statusSummary: "",
                recentLogs: "",
                remotes: "",
                error: check.error
            )
        }

        var branchName: String? = nil
        let branchCheck = runGit(args: ["branch", "--show-current"], cwd: cwd)
        if !branchCheck.output.isEmpty {
            branchName = branchCheck.output
        } else {
            let headCheck = runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd)
            if !headCheck.output.isEmpty {
                branchName = headCheck.output
            }
        }

        let status = runGit(args: ["status", "--short", "--branch"], cwd: cwd).output
        let logs = runGit(args: ["log", "-n", "3", "--oneline"], cwd: cwd).output
        let remotes = runGit(args: ["remote", "-v"], cwd: cwd).output

        return GitState(
            isRepo: true,
            branch: branchName,
            statusSummary: status,
            recentLogs: logs,
            remotes: remotes
        )
    }
}
