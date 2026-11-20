import Foundation

public class GitAgentEngine {
    public let fmClient: FMClientProtocol
    public let maxRetries: Int
    public let autoConfirm: Bool
    public let verbose: Bool
    public let cwd: String?

    public init(
        fmClient: FMClientProtocol? = nil,
        maxRetries: Int = 3,
        autoConfirm: Bool = true,
        verbose: Bool = false,
        cwd: String? = nil
    ) {
        self.fmClient = fmClient ?? AppleFMClient()
        self.maxRetries = maxRetries
        self.autoConfirm = autoConfirm
        self.verbose = verbose
        self.cwd = cwd
    }

    public func checkPrerequisites() -> Bool {
        if !fmClient.isAvailable() {
            UI.error("""
            Apple Foundation Models (`fm`) CLI is not available or system model is offline.
            Ensure macOS 15+ / Apple Intelligence is enabled and `fm available` returns success.
            """)
            return false
        }
        return true
    }

    public func executeTask(_ task: String) async -> Bool {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        guard checkPrerequisites() else { return false }

        // 1. Capture git context
        let gitState = GitContextInspector.getGitState(cwd: cwd)
        if verbose {
            UI.info("Inspected git state:\n\(gitState.toPromptContext())")
        }

        // 2. Query Apple FM model
        UI.info("Consulting Apple Foundation Model for task: \(UI.Style.bold)'\(trimmed)'\(UI.Style.reset)...")
        let plan: GitPlan
        do {
            plan = try await fmClient.planAction(task: trimmed, gitContext: gitState.toPromptContext())
        } catch {
            UI.error("Failed to query Apple Foundation Model: \(error.localizedDescription)")
            return false
        }

        if plan.command.isEmpty {
            UI.warning("Model concluded no git command is necessary for this task.")
            if !plan.explanation.isEmpty {
                print("Explanation: \(plan.explanation)")
            }
            return true
        }

        UI.modelMsg(
            thought: verbose ? plan.thought : "",
            command: plan.command,
            explanation: plan.explanation
        )

        // 3. Execute command (without permission by default)
        let currentCmd = plan.command
        if !autoConfirm {
            print("\(UI.Style.bold)Execute this command? [Y/n]: \(UI.Style.reset)", terminator: "")
            guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  line.isEmpty || line == "y" || line == "yes" else {
                UI.warning("Execution cancelled by user.")
                return false
            }
        }

        UI.executingMsg(currentCmd)
        let result = CommandExecutor.execute(command: currentCmd, cwd: cwd)

        // 4. Handle result
        if result.isSuccess {
            if !result.combinedOutput.isEmpty {
                print("\(UI.Style.dim)\(result.combinedOutput)\(UI.Style.reset)")
            }
            UI.success("Command executed successfully!")
            printPostState()
            return true
        }

        // Failure - start self-healing recovery loop
        UI.error("Command exited with code \(result.exitCode)")
        if !result.combinedOutput.isEmpty {
            print("\(UI.Style.brightRed)\(result.combinedOutput)\(UI.Style.reset)")
        }

        var lastFailedCmd = currentCmd
        var lastResult = result

        for attempt in 1...maxRetries {
            UI.retryMsg(attempt: attempt, maxRetries: maxRetries)
            let updatedState = GitContextInspector.getGitState(cwd: cwd)

            let recoveryPlan: GitPlan
            do {
                recoveryPlan = try await fmClient.planRecovery(
                    task: trimmed,
                    failedCommand: lastFailedCmd,
                    exitCode: lastResult.exitCode,
                    output: lastResult.combinedOutput,
                    gitContext: updatedState.toPromptContext()
                )
            } catch {
                UI.error("Failed to query model for error recovery: \(error.localizedDescription)")
                return false
            }

            if recoveryPlan.command.isEmpty {
                UI.error("Model could not determine a recovery command.")
                if !recoveryPlan.explanation.isEmpty {
                    print("Model note: \(recoveryPlan.explanation)")
                }
                return false
            }

            UI.modelMsg(
                thought: verbose ? recoveryPlan.thought : "",
                command: recoveryPlan.command,
                explanation: recoveryPlan.explanation
            )

            if !autoConfirm {
                print("\(UI.Style.bold)Execute fix command? [Y/n]: \(UI.Style.reset)", terminator: "")
                guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                      line.isEmpty || line == "y" || line == "yes" else {
                    UI.warning("Recovery cancelled by user.")
                    return false
                }
            }

            UI.executingMsg(recoveryPlan.command)
            lastFailedCmd = recoveryPlan.command
            lastResult = CommandExecutor.execute(command: recoveryPlan.command, cwd: cwd)

            if lastResult.isSuccess {
                if !lastResult.combinedOutput.isEmpty {
                    print("\(UI.Style.dim)\(lastResult.combinedOutput)\(UI.Style.reset)")
                }
                UI.success("Recovery successful on attempt \(attempt)! Goal achieved.")
                printPostState()
                return true
            }

            UI.error("Fix command failed with code \(lastResult.exitCode)")
            if !lastResult.combinedOutput.isEmpty {
                print("\(UI.Style.brightRed)\(lastResult.combinedOutput)\(UI.Style.reset)")
            }
        }

        UI.error("Reached maximum retries (\(maxRetries)). Task could not be automatically resolved.")
        return false
    }

    private func printPostState() {
        let state = GitContextInspector.getGitState(cwd: cwd)
        if state.isRepo {
            let branch = state.branch ?? "no branch"
            let lines = state.statusSummary.components(separatedBy: .newlines)
            let short = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "clean"
            print("\(UI.Style.dim)↳ Current state: [branch: \(branch)] \(short)\(UI.Style.reset)\n")
        }
    }
}
