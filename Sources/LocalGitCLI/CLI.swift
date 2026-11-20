import Foundation
import LocalGitCore

public enum CLI {
    public static func repl(engine: GitAgentEngine) async {
        UI.printBanner()

        let state = GitContextInspector.getGitState(cwd: engine.cwd)
        if !state.isRepo {
            UI.warning("Current directory is not a Git repository. You can say 'initialize git repository' to start.")
        }

        print("\(UI.Style.dim)Type your task in plain English (e.g. 'stage all files and commit with feat: initial commit').")
        print("Commands: 'status' (view git status), 'help', 'exit' or 'quit' to leave.\(UI.Style.reset)\n")

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

            let lower = input.lowercased()
            if lower == "exit" || lower == "quit" || lower == "q" {
                print("Goodbye!")
                break
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
                    - \(UI.Style.cyan)status\(UI.Style.reset) : Show detailed git status
                    - \(UI.Style.cyan)help\(UI.Style.reset)   : Show this help text
                    - \(UI.Style.cyan)exit\(UI.Style.reset)   : Exit the agent

                """)
                continue
            }

            if lower == "status" {
                let s = GitContextInspector.getGitState(cwd: engine.cwd)
                print("\n\(s.toPromptContext())\n")
                continue
            }

            _ = await engine.executeTask(input)
        }
    }

    public static func run(args: [String]) async {
        var autoConfirm = true
        var maxRetries = 3
        var verbose = false
        var cwd: String? = nil
        var taskTokens: [String] = []

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
            case "-C", "--cwd":
                if i + 1 < args.count {
                    cwd = args[i + 1]
                    i += 1
                }
            case "-h", "--help":
                print("""
                Usage: localgit [options] [task...]

                Options:
                  -a, --ask             Ask for confirmation before executing commands (default: run without permission)
                  -r, --max-retries <n> Max self-healing recovery attempts upon error (default: 3)
                  -v, --verbose         Print detailed model reasoning and context
                  -C, --cwd <path>      Target directory of git repository
                  -h, --help            Show this help information
                """)
                return
            default:
                if !arg.hasPrefix("-") {
                    taskTokens.append(arg)
                }
            }
            i += 1
        }

        let engine = GitAgentEngine(
            maxRetries: maxRetries,
            autoConfirm: autoConfirm,
            verbose: verbose,
            cwd: cwd
        )

        if taskTokens.isEmpty {
            await repl(engine: engine)
        } else {
            let task = taskTokens.joined(separator: " ")
            let success = await engine.executeTask(task)
            exit(success ? 0 : 1)
        }
    }
}
