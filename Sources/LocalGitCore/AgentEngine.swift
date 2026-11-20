import Foundation

/// Represents an immutable log entry of a completed task within a session.
///
/// Used exclusively when persistent session history (`--with-history` / `-H`) is enabled,
/// allowing the model to know what actions were taken previously in the session.
public struct TaskRecord: Equatable {
    /// The user's original task description.
    public let task: String

    /// The list of shell commands executed while attempting this task.
    public let executedCommands: [String]

    /// Whether the task ended in success or failed after exhausting retries.
    public let success: Bool

    /// The model's explanation of the outcome.
    public let explanation: String

    /// Timestamp when the task was recorded.
    public let timestamp: Date

    /// Memberwise initializer.
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

/// The core autonomous agent orchestrator for LocalGit.
///
/// `GitAgentEngine` coordinates the lifecycle of natural language Git tasks:
/// 1. Inspects the active repository environment via `GitContextInspector`.
/// 2. Asks the Apple Foundation Model for the exact command to run (Step 1).
/// 3. Executes the command autonomously in the terminal without asking for permission (default).
/// 4. If successful, feeds the terminal output back to the model to synthesize a friendly summary (Step 2).
/// 5. If an error occurs, feeds the failure details (`stderr`, exit code) back to the model, diagnoses the root cause,
///    and executes corrective recovery commands until resolved or retries are exhausted.
/// 6. Cleans up session history upon completion (default mode) to prevent context pollution on local LLMs.
public class GitAgentEngine {
    /// The model interface used for action planning, diagnosis, and output synthesis.
    public let fmClient: FMClientProtocol

    /// The maximum number of self-healing retry attempts allowed if commands fail.
    public let maxRetries: Int

    /// When `true`, executes commands autonomously without prompting `[Y/n]`. Defaults to `true`.
    public let autoConfirm: Bool

    /// When `true`, displays detailed internal model reasoning and raw responses.
    public let verbose: Bool

    /// When `true`, preserves task history across multiple tasks in the session. Defaults to `false`.
    public let withHistory: Bool

    /// Target Git repository directory (defaults to current process working directory).
    public let cwd: String?

    /// Active session history records (populated only when `withHistory == true`).
    public private(set) var sessionHistory: [TaskRecord] = []

    /// Initializes a `GitAgentEngine` instance.
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

    /// Wipes all accumulated session history clean.
    public func clearHistory() {
        sessionHistory.removeAll()
    }

    /// Formats the session history into a concise text block for the LLM prompt.
    ///
    /// - Returns: A formatted string of prior tasks and their executed commands, or `nil` if history is empty.
    public func formattedHistory() -> String? {
        guard withHistory, !sessionHistory.isEmpty else { return nil }
        return sessionHistory.enumerated().map { index, record in
            let cmds = record.executedCommands.isEmpty ? "None" : record.executedCommands.joined(separator: " && ")
            let status = record.success ? "Success" : "Failed"
            return "- Previous Task \(index + 1): \"\(record.task)\" [\(status)] -> Command: `\(cmds)`"
        }.joined(separator: "\n")
    }

    /// Verifies that the Apple Foundation Model backend is accessible before attempting work.
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

    /// Prompts the user for manual confirmation if `--ask` mode is active (`autoConfirm == false`).
    ///
    /// - Parameter command: The proposed shell command.
    /// - Returns: `true` if the user approves execution; `false` if cancelled.
    private func confirmExecutionIfNeeded(for command: String) -> Bool {
        guard !autoConfirm else { return true }
        print("\(UI.Style.bold)Execute this command? [Y/n]: \(UI.Style.reset)", terminator: "")
        guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              line.isEmpty || line == "y" || line == "yes" else {
            UI.warning("Execution cancelled by user.")
            return false
        }
        return true
    }

    /// Dispatches a shell command, logs its execution banner, and records it into the command list.
    private func dispatchCommand(
        _ command: String,
        into executedCommands: inout [String]
    ) -> ExecutionResult {
        UI.printCommand(command)
        executedCommands.append(command)
        return CommandExecutor.execute(command: command, cwd: cwd)
    }

    /// Step 2 of the workflow: asks the local LLM to translate raw terminal output into a friendly user summary.
    private func synthesizeSuccessOutput(
        task: String,
        command: String,
        result: ExecutionResult
    ) async -> String {
        do {
            return try await fmClient.synthesizeOutput(
                task: task,
                executedCommand: command,
                exitCode: result.exitCode,
                rawTerminalOutput: result.combinedOutput
            )
        } catch {
            return !result.combinedOutput.isEmpty ? result.combinedOutput : "Command completed successfully."
        }
    }

    /// Executes the self-healing error recovery loop when a Git command fails.
    ///
    /// - Parameters:
    ///   - task: The original user task.
    ///   - initialFailedCmd: The command that produced the error.
    ///   - initialResult: The execution result containing exit code and error output.
    ///   - executedCommands: Accumulated list of executed commands.
    /// - Returns: A tuple indicating whether recovery succeeded and the final explanation message.
    private func executeRecoveryLoop(
        task: String,
        initialFailedCmd: String,
        initialResult: ExecutionResult,
        executedCommands: inout [String]
    ) async -> (success: Bool, lastExplanation: String) {
        var lastFailedCmd = initialFailedCmd
        var lastResult = initialResult
        var lastExplanation = ""

        for attempt in 1...maxRetries {
            UI.retryMsg(attempt: attempt, maxRetries: maxRetries)
            let updatedState = GitContextInspector.getGitState(cwd: cwd)

            // Query model for diagnosis and fix
            let recoveryPlan: GitPlan
            do {
                recoveryPlan = try await fmClient.planRecovery(
                    task: task,
                    failedCommand: lastFailedCmd,
                    exitCode: lastResult.exitCode,
                    output: lastResult.combinedOutput,
                    gitContext: updatedState.toPromptContext()
                )
            } catch {
                UI.error("Failed to query model for error recovery: \(error.localizedDescription)")
                return (false, "Error recovery query failed.")
            }

            lastExplanation = recoveryPlan.explanation

            // Display diagnosis thinking in Bright Magenta
            if !recoveryPlan.thought.isEmpty {
                UI.printThinking(recoveryPlan.thought)
            }

            if recoveryPlan.command.isEmpty {
                UI.error("Model could not determine a recovery command.")
                if !recoveryPlan.explanation.isEmpty {
                    UI.printOutput(recoveryPlan.explanation)
                }
                return (false, recoveryPlan.explanation)
            }

            // Check confirmation if --ask mode is active
            guard confirmExecutionIfNeeded(for: recoveryPlan.command) else {
                return (false, "User cancelled recovery.")
            }

            // Run corrective command
            lastFailedCmd = recoveryPlan.command
            lastResult = dispatchCommand(recoveryPlan.command, into: &executedCommands)

            if lastResult.isSuccess {
                // Synthesize final resolution output
                let outputToShow = await synthesizeSuccessOutput(
                    task: task,
                    command: recoveryPlan.command,
                    result: lastResult
                )
                UI.printOutput(outputToShow)
                printPostState()
                return (true, lastExplanation)
            }

            // Still failed - print error in Red and loop again
            let fixErrorMsg = !lastResult.combinedOutput.isEmpty
                ? lastResult.combinedOutput
                : "Fix command failed with code \(lastResult.exitCode)"
            UI.printTerminalError(fixErrorMsg)
        }

        UI.error("Reached maximum retries (\(maxRetries)). Task could not be automatically resolved.")
        return (false, lastExplanation)
    }

    /// Handles cleanup or persistence of task records depending on `withHistory` mode.
    private func handleTaskFinalization(
        task: String,
        executedCommands: [String],
        finalSuccess: Bool,
        lastExplanation: String
    ) {
        if !withHistory {
            // Default Mode: Clear history immediately upon task completion to keep local model context clean
            clearHistory()
        } else {
            // Flag Mode (-H / --with-history): Save record in memory for subsequent tasks in this session
            sessionHistory.append(TaskRecord(
                task: task,
                executedCommands: executedCommands,
                success: finalSuccess,
                explanation: lastExplanation
            ))
        }
    }

    /// Executes a natural language Git task through the complete autonomous agent lifecycle.
    ///
    /// Pipeline:
    /// 1. Formats and prints user task in Yellow.
    /// 2. Gathers current Git repository state.
    /// 3. Step 1 (Action Generation): Asks the Apple Foundation Model for the exact Git command.
    /// 4. Prints model reasoning in Magenta and proposed command in Cyan.
    /// 5. Executes command autonomously in terminal.
    /// 6. If successful: Step 2 (Output Synthesis): Asks model to translate terminal output into user summary (Green).
    /// 7. If failed: Prints error in Red, enters self-healing recovery loop, diagnoses failure, and executes fix.
    /// 8. Finalizes session history according to `withHistory` mode.
    ///
    /// - Parameter task: Plain English Git goal (e.g. "create branch dev and switch to it").
    /// - Returns: `true` if the task was completed successfully; otherwise `false`.
    public func executeTask(_ task: String) async -> Bool {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard checkPrerequisites() else { return false }

        // Format 1: Display User Input in Bright Yellow
        UI.printUserInput(trimmed)

        var executedCommands: [String] = []
        var finalSuccess = false
        var lastExplanation = ""

        defer {
            handleTaskFinalization(
                task: trimmed,
                executedCommands: executedCommands,
                finalSuccess: finalSuccess,
                lastExplanation: lastExplanation
            )
        }

        // Gather live repository context
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

        // Format 2: Display Model Thinking in Bright Magenta
        if !plan.thought.isEmpty {
            UI.printThinking(plan.thought)
        }

        // Handle case where model determined no command is needed
        if plan.command.isEmpty {
            let directMsg = !plan.explanation.isEmpty ? plan.explanation : "No git command needed for this task."
            UI.printOutput(directMsg)
            finalSuccess = true
            return true
        }

        // Check confirmation if user explicitly asked for confirmation (--ask)
        guard confirmExecutionIfNeeded(for: plan.command) else {
            return false
        }

        // Execute proposed command in terminal
        let result = dispatchCommand(plan.command, into: &executedCommands)

        // Command Succeeded: Step 2 - Synthesize terminal output with LLM
        if result.isSuccess {
            let outputToShow = await synthesizeSuccessOutput(
                task: trimmed,
                command: plan.command,
                result: result
            )
            UI.printOutput(outputToShow)
            printPostState()
            finalSuccess = true
            return true
        }

        // Command Failed: Print error output in Red and enter self-healing recovery loop
        let errorMsg = !result.combinedOutput.isEmpty
            ? result.combinedOutput
            : "Command exited with error code \(result.exitCode)"
        UI.printTerminalError(errorMsg)

        let recoveryResult = await executeRecoveryLoop(
            task: trimmed,
            initialFailedCmd: plan.command,
            initialResult: result,
            executedCommands: &executedCommands
        )

        finalSuccess = recoveryResult.success
        lastExplanation = recoveryResult.lastExplanation
        return finalSuccess
    }

    /// Prints a one-line summary of current branch and status after task execution.
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
