import Foundation
import LocalGitCore

/// Parsed command line options container.
public struct CommandLineOptions {
    /// When `true`, executes commands autonomously without prompting (default).
    public let autoConfirm: Bool

    /// Maximum number of self-healing error recovery attempts.
    public let maxRetries: Int

    /// When `true`, displays detailed model reasoning and internal logs.
    public let verbose: Bool

    /// When `true`, preserves task history across multiple tasks in the session.
    public let withHistory: Bool

    /// Target Git repository directory path (if specified via `-C`).
    public let cwd: String?

    /// Tokens representing the single-shot task string, or empty if entering REPL.
    public let taskTokens: [String]

    /// Whether `--help` or `-h` was requested.
    public let showHelp: Bool

    /// Memberwise initializer.
    public init(
        autoConfirm: Bool = true,
        maxRetries: Int = 3,
        verbose: Bool = false,
        withHistory: Bool = false,
        cwd: String? = nil,
        taskTokens: [String] = [],
        showHelp: Bool = false
    ) {
        self.autoConfirm = autoConfirm
        self.maxRetries = maxRetries
        self.verbose = verbose
        self.withHistory = withHistory
        self.cwd = cwd
        self.taskTokens = taskTokens
        self.showHelp = showHelp
    }
}

/// Command Line Interface coordinator and Interactive REPL Shell for LocalGit.
public enum CLI {

    /// Prints the command-line usage and options guide to standard output.
    public static func printHelp() {
        print("""
        Usage: localgit [options] [task...]

        Options:
          -a, --ask             Ask for confirmation before executing commands (default: run without permission)
          -H, --with-history    Retain session task history across multiple tasks (default: cleared after each task)
          -r, --max-retries <n> Max self-healing recovery attempts upon error (default: 3)
          -v, --verbose         Print detailed model reasoning and context
          -C, --cwd <path>      Target directory of git repository
          -h, --help            Show this help information
        """)
    }

    /// Evaluates whether the user's input is a built-in shell command (`status`, `history`, `clear`, `help`, `exit`).
    ///
    /// - Parameters:
    ///   - input: The raw string entered by the user.
    ///   - engine: The active `GitAgentEngine` instance.
    /// - Returns: `true` if the input was handled as a built-in command; `false` if it should be sent to the LLM.
    public static func handleSpecialCommand(input: String, engine: GitAgentEngine) -> (handled: Bool, shouldExit: Bool) {
        let lower = input.lowercased()

        if lower == "exit" || lower == "quit" || lower == "q" {
            print("Goodbye!")
            return (true, true)
        }

        if lower == "help" || lower == "?" {
            print("""

            \(UI.Style.bold)LocalGit Help:\(UI.Style.reset)
              Simply type what you want to do with Git in plain English!
              Examples:
                - "undo my last commit and keep changes staged"
                - "create a new branch named bugfix/auth and switch to it"
                - "stage everything and commit with message 'fix: login issue'"
                - "stash all current uncommitted changes"
                - "show last 5 commits with graphs"

              Special Commands:
                - \(UI.Style.cyan)status\(UI.Style.reset)  : Show detailed git status
                - \(UI.Style.cyan)history\(UI.Style.reset) : View active session task history
                - \(UI.Style.cyan)clear\(UI.Style.reset)   : Manually wipe session history
                - \(UI.Style.cyan)help\(UI.Style.reset)    : Show this help text
                - \(UI.Style.cyan)exit\(UI.Style.reset)    : Exit the agent

            """)
            return (true, false)
        }

        if lower == "status" {
            let s = GitContextInspector.getGitState(cwd: engine.cwd)
            print("\n\(s.toPromptContext())\n")
            return (true, false)
        }

        if lower == "clear" || lower == "reset" {
            engine.clearHistory()
            UI.success("Session history wiped clean.")
            return (true, false)
        }

        if lower == "history" {
            if !engine.withHistory {
                UI.info("Default mode is active: task history is cleared after each task completion. Launch with -H or --with-history to retain history.")
            } else if let hist = engine.formattedHistory() {
                print("\n\(UI.Style.bold)Session Task History:\(UI.Style.reset)\n\(hist)\n")
            } else {
                UI.info("No tasks recorded in history yet.")
            }
            return (true, false)
        }

        return (false, false)
    }

    /// Interactive REPL loop. Prompts the developer continuously for Git tasks in plain English.
    public static func repl(engine: GitAgentEngine) async {
        UI.printBanner()

        let state = GitContextInspector.getGitState(cwd: engine.cwd)
        if !state.isRepo {
            UI.warning("Current directory is not a Git repository. You can say 'initialize git repository' to start.")
        }

        let historyModeStr = engine.withHistory
            ? "\(UI.Style.brightGreen)Enabled (--with-history)\(UI.Style.reset)"
            : "\(UI.Style.brightYellow)Cleared per task (Default)\(UI.Style.reset)"

        print("\(UI.Style.dim)Session History: [\(historyModeStr)\(UI.Style.dim)]")
        print("Type your task in plain English (e.g. 'stage all files and commit with feat: initial commit').")
        print("Commands: 'status', 'history', 'clear', 'help', 'exit' or 'quit' to leave.\(UI.Style.reset)\n")

        while true {
            let curState = GitContextInspector.getGitState(cwd: engine.cwd)
            let branchStr = (curState.isRepo && curState.branch != nil) ? curState.branch! : "no-repo"
            let prompt = "\(UI.Style.brightGreen)localgit\(UI.Style.reset) (\(UI.Style.brightCyan)\(branchStr)\(UI.Style.reset)) > "

            print(prompt, terminator: "")
            guard let line = readLine() else {
                print("\nGoodbye!")
                break
            }

            let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { continue }

            let (handled, shouldExit) = handleSpecialCommand(input: input, engine: engine)
            if shouldExit { break }
            if handled { continue }

            // Dispatch task through autonomous agent engine
            _ = await engine.executeTask(input)
        }
    }

    /// Parses command-line arguments into a strongly-typed `CommandLineOptions` structure.
    public static func parseCommandLineOptions(from args: [String]) -> CommandLineOptions {
        var autoConfirm = true
        var maxRetries = 3
        var verbose = false
        var withHistory = false
        var cwd: String? = nil
        var taskTokens: [String] = []
        var showHelp = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "-a", "--ask":
                autoConfirm = false
            case "-r", "--max-retries":
                if i + 1 < args.count, let val = Int(args[i + 1]) {
                    maxRetries = val
                    i += 1
                }
            case "-v", "--verbose":
                verbose = true
            case "-H", "--with-history":
                withHistory = true
            case "-C", "--cwd":
                if i + 1 < args.count {
                    cwd = args[i + 1]
                    i += 1
                }
            case "-h", "--help":
                showHelp = true
            default:
                if !arg.hasPrefix("-") {
                    taskTokens.append(arg)
                }
            }
            i += 1
        }

        return CommandLineOptions(
            autoConfirm: autoConfirm,
            maxRetries: maxRetries,
            verbose: verbose,
            withHistory: withHistory,
            cwd: cwd,
            taskTokens: taskTokens,
            showHelp: showHelp
        )
    }

    /// Application main entrypoint coordinator.
    ///
    /// Evaluates arguments:
    /// - If `--help`, displays usage options.
    /// - If task tokens are present, executes single-shot task and exits with appropriate status code.
    /// - If no task arguments are provided, enters interactive REPL session.
    public static func run(args: [String]) async {
        let options = parseCommandLineOptions(from: args)

        if options.showHelp {
            printHelp()
            return
        }

        let engine = GitAgentEngine(
            maxRetries: options.maxRetries,
            autoConfirm: options.autoConfirm,
            verbose: options.verbose,
            withHistory: options.withHistory,
            cwd: options.cwd
        )

        if options.taskTokens.isEmpty {
            await repl(engine: engine)
        } else {
            let task = options.taskTokens.joined(separator: " ")
            let success = await engine.executeTask(task)
            exit(success ? 0 : 1)
        }
    }
}
