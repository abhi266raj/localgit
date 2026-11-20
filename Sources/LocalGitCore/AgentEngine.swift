import Foundation

public struct TaskRecord: Equatable {
    public let task: String
    public let executedCommands: [String]
    public let success: Bool
    public let explanation: String
    public let timestamp: Date

    public init(
        task: String,
        executedCommands: [String],
        success: Bool,
        explanation: String,
        timestamp: Date = Date()
    ) {
        self.task = task
        self.executedCommands = executedCommands
        self.success = success
        self.explanation = explanation
        self.timestamp = timestamp
    }
}

public class GitAgentEngine {
    public let fmClient: FMClientProtocol
    public let maxRetries: Int
    public let autoConfirm: Bool
    public let verbose: Bool
    public let withHistory: Bool
    public let cwd: String?

    public private(set) var sessionHistory: [TaskRecord] = []

    public init(
        fmClient: FMClientProtocol? = nil,
        maxRetries: Int = 3,
        autoConfirm: Bool = true,
        verbose: Bool = false,
        withHistory: Bool = false,
        cwd: String? = nil
    ) {
        self.fmClient = fmClient ?? AppleFMClient()
        self.maxRetries = maxRetries
        self.autoConfirm = autoConfirm
        self.verbose = verbose
        self.withHistory = withHistory
        self.cwd = cwd
    }

    public func clearHistory() {
        sessionHistory.removeAll()
    }

    public func formattedHistory() -> String? {
        guard withHistory, !sessionHistory.isEmpty else { return nil }
        return sessionHistory.enumerated().map { index, record in
            let cmds = record.executedCommands.isEmpty ? "None" : record.executedCommands.joined(separator: " && ")
            let status = record.success ? "Success" : "Failed"
            return "- Previous Task \(index + 1): \"\(record.task)\" [\(status)] -> Command: `\(cmds)`"
        }.joined(separator: "\n")
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

        // Format 1: Display User Input in separate color (Yellow)
        UI.printUserInput(trimmed)

        var executedCommands: [String] = []
        var finalSuccess = false
        var lastExplanation = ""

        defer {
            if !withHistory {
                // Default mode: local LLM history is cleared immediately once task is completed
                clearHistory()
            } else {
                sessionHistory.append(TaskRecord(
                    task: trimmed,
                    executedCommands: executedCommands,
                    success: finalSuccess,
                    explanation: lastExplanation
                ))
            }
        }

        // Capture git context
        let gitState = GitContextInspector.getGitState(cwd: cwd)
        if verbose {
            UI.info("Inspected git state:\n\(gitState.toPromptContext())")
            if let hist = formattedHistory() {
                UI.info("Active session history:\n\(hist)")
            }
        }

        // Step 1: Query Apple FM model to plan the action
        UI.info("Consulting Apple Foundation Model for git command...")
        let plan: GitPlan
        do {
            plan = try await fmClient.planAction(
                task: trimmed,
                gitContext: gitState.toPromptContext(),
                sessionHistory: formattedHistory()
            )
        } catch {
            UI.error("Failed to query Apple Foundation Model: \(error.localizedDescription)")
            return false
        }

        lastExplanation = plan.explanation

        // Format 2: Display Model Thinking in separate color (Magenta)
        if !plan.thought.isEmpty {
            UI.printThinking(plan.thought)
        }

        if plan.command.isEmpty {
            let directMsg = !plan.explanation.isEmpty ? plan.explanation : "No git command needed for this task."
            // Format 3: Display Output in separate color (Green)
            UI.printOutput(directMsg)
            finalSuccess = true
            return true
        }

        let currentCmd = plan.command
        if !autoConfirm {
            print("\(UI.Style.bold)Execute this command? [Y/n]: \(UI.Style.reset)", terminator: "")
            guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  line.isEmpty || line == "y" || line == "yes" else {
                UI.warning("Execution cancelled by user.")
                return false
            }
        }

        // Execute command in terminal
        UI.printCommand(currentCmd)
        executedCommands.append(currentCmd)
        let result = CommandExecutor.execute(command: currentCmd, cwd: cwd)

        // Handle success: Step 2 - Ask local LLM what output to show to the user
        if result.isSuccess {
            let outputToShow: String
            do {
                outputToShow = try await fmClient.synthesizeOutput(
                    task: trimmed,
                    executedCommand: currentCmd,
                    exitCode: result.exitCode,
                    rawTerminalOutput: result.combinedOutput
                )
            } catch {
                outputToShow = !result.combinedOutput.isEmpty ? result.combinedOutput : "Command completed successfully."
            }

            // Format 3: Display Output in separate color (Green)
            UI.printOutput(outputToShow)
            printPostState()
            finalSuccess = true
            return true
        }

        // If error is there: Show error from message (in Red)
        let errorMsg = !result.combinedOutput.isEmpty ? result.combinedOutput : "Command exited with error code \(result.exitCode)"
        UI.printTerminalError(errorMsg)

        var lastFailedCmd = currentCmd
        var lastResult = result

        // Recovery loop: diagnose with model and retry
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

            lastExplanation = recoveryPlan.explanation

            // Format 2: Display Model Thinking during diagnosis (Magenta)
            if !recoveryPlan.thought.isEmpty {
                UI.printThinking(recoveryPlan.thought)
            }

            if recoveryPlan.command.isEmpty {
                UI.error("Model could not determine a recovery command.")
                if !recoveryPlan.explanation.isEmpty {
                    UI.printOutput(recoveryPlan.explanation)
                }
                return false
            }

            if !autoConfirm {
                print("\(UI.Style.bold)Execute fix command? [Y/n]: \(UI.Style.reset)", terminator: "")
                guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                      line.isEmpty || line == "y" || line == "yes" else {
                    UI.warning("Recovery cancelled by user.")
                    return false
                }
            }

            // Execute recovery command in terminal
            UI.printCommand(recoveryPlan.command)
            executedCommands.append(recoveryPlan.command)
            lastFailedCmd = recoveryPlan.command
            lastResult = CommandExecutor.execute(command: recoveryPlan.command, cwd: cwd)

            if lastResult.isSuccess {
                // Step 2: Ask local LLM what output to show to the user
                let outputToShow: String
                do {
                    outputToShow = try await fmClient.synthesizeOutput(
                        task: trimmed,
                        executedCommand: recoveryPlan.command,
                        exitCode: lastResult.exitCode,
                        rawTerminalOutput: lastResult.combinedOutput
                    )
                } catch {
                    outputToShow = !lastResult.combinedOutput.isEmpty ? lastResult.combinedOutput : "Recovery command executed successfully."
                }

                // Format 3: Display Output in separate color (Green)
                UI.printOutput(outputToShow)
                printPostState()
                finalSuccess = true
                return true
            }

            // Show error from message again (Red)
            let fixErrorMsg = !lastResult.combinedOutput.isEmpty ? lastResult.combinedOutput : "Fix command failed with code \(lastResult.exitCode)"
            UI.printTerminalError(fixErrorMsg)
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
