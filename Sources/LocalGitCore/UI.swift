import Foundation

/// Terminal UI formatting, ANSI styling, and color-coded output utilities.
///
/// LocalGit enforces a strict visual hierarchy using standard ANSI escape codes:
/// - 👤 **User Task** (`Style.userInput` - Bright Yellow): Echoes what the developer asked.
/// - 🧠 **Model Thinking** (`Style.thinking` - Bright Magenta): Displays the LLM's chain-of-thought analysis.
/// - ⚡ **Command Execution** (`Style.command` - Cyan): Shows the exact terminal shell command to be run.
/// - ✖ **Terminal Error** (`Style.error` - Bright Red): Highlights stderr or non-zero exit codes.
/// - 💬 **Synthesized Output** (`Style.output` - Bright Green): Final synthesized explanation to the user.
public enum UI {

    /// ANSI Escape sequence definitions for terminal styling.
    public enum Style {
        public static let reset = "\u{001B}[0m"
        public static let bold = "\u{001B}[1m"
        public static let dim = "\u{001B}[2m"
        public static let italic = "\u{001B}[3m"

        // Base ANSI Colors
        public static let red = "\u{001B}[31m"
        public static let green = "\u{001B}[32m"
        public static let yellow = "\u{001B}[33m"
        public static let blue = "\u{001B}[34m"
        public static let magenta = "\u{001B}[35m"
        public static let cyan = "\u{001B}[36m"

        // High-Intensity Bright Colors
        public static let brightRed = "\u{001B}[91m"
        public static let brightGreen = "\u{001B}[92m"
        public static let brightYellow = "\u{001B}[93m"
        public static let brightBlue = "\u{001B}[94m"
        public static let brightMagenta = "\u{001B}[95m"
        public static let brightCyan = "\u{001B}[96m"

        // Semantic Role-Based Color Palette
        /// Bold Bright Yellow: Applied to user input prompts and task declarations.
        public static let userInput = "\u{001B}[1;93m"

        /// Bold Bright Magenta: Applied to model internal thinking, reasoning, and diagnosis.
        public static let thinking  = "\u{001B}[1;95m"

        /// Bold Cyan: Applied to proposed and currently executing shell commands.
        public static let command   = "\u{001B}[1;36m"

        /// Bold Bright Green: Applied to synthesized output messages and successful completions.
        public static let output    = "\u{001B}[1;92m"

        /// Bold Bright Red: Applied to error outputs, failed commands, and alert messages.
        public static let error     = "\u{001B}[1;91m"

        /// Bright Blue: Applied to informational notices, status banners, and system messages.
        public static let info      = "\u{001B}[94m"
    }

    /// Prints the ASCII art banner and application title to standard output.
    public static func printBanner() {
        let banner = """
        \(Style.command)
          _                     _  ____ _ _   
         | |    ___   ___ __ _| |/ ___(_) |_ 
         | |   / _ \\ / __/ _` | | |  _| | __|
         | |__| (_) | (_| (_| | | |_| | | |_ 
         |_____\\___/ \\___\\__,_|_|\\____|_|\\__|
        \(Style.reset)\(Style.dim) Local Apple Foundation Model Git Agent in Swift (powered by `fm`)\(Style.reset)
        """
        print(banner)
    }

    /// Formats and prints the user's task prompt in Bright Yellow.
    public static func printUserInput(_ text: String) {
        print("\(Style.userInput)👤 User Task:\(Style.reset) \(Style.userInput)\(text)\(Style.reset)")
    }

    /// Formats and prints the model's internal reasoning/thinking in Bright Magenta.
    public static func printThinking(_ text: String) {
        print("\(Style.thinking)🧠 Thinking:\(Style.reset) \(Style.thinking)\(text)\(Style.reset)")
    }

    /// Formats and prints the command being auto-executed in Cyan.
    public static func printCommand(_ cmd: String) {
        print("\(Style.command)⚡ Executing (auto-run):\(Style.reset) \(Style.command)\(cmd)\(Style.reset)")
    }

    /// Formats and prints terminal error output in Bright Red.
    public static func printTerminalError(_ err: String) {
        print("\(Style.error)✖ Error Output:\(Style.reset)\n\(Style.error)\(err)\(Style.reset)")
    }

    /// Formats and prints the model-synthesized output message in Bright Green.
    public static func printOutput(_ text: String) {
        print("\(Style.output)💬 Output:\(Style.reset) \(Style.output)\(text)\(Style.reset)")
    }

    /// Prints a generic informational notice in Bright Blue.
    public static func info(_ msg: String) {
        print("\(Style.info)ℹ \(msg)\(Style.reset)")
    }

    /// Prints a success notice with a green checkmark.
    public static func success(_ msg: String) {
        print("\(Style.output)✔ \(msg)\(Style.reset)")
    }

    /// Prints a warning notice with a yellow triangle.
    public static func warning(_ msg: String) {
        print("\(Style.userInput)▲ \(msg)\(Style.reset)")
    }

    /// Prints an error message with a red cross.
    public static func error(_ msg: String) {
        print("\(Style.error)✖ \(msg)\(Style.reset)")
    }

    /// Prints a retry progress notice during the self-healing error recovery loop.
    public static func retryMsg(attempt: Int, maxRetries: Int) {
        print("\(Style.userInput)🔄 Error encountered. Asking Apple FM model to diagnose & fix (attempt \(attempt)/\(maxRetries))...\(Style.reset)")
    }
}
