import Foundation

public enum UI {
    public enum Style {
        public static let reset = "\u{001B}[0m"
        public static let bold = "\u{001B}[1m"
        public static let dim = "\u{001B}[2m"
        public static let italic = "\u{001B}[3m"

        // Basic ANSI colors
        public static let red = "\u{001B}[31m"
        public static let green = "\u{001B}[32m"
        public static let yellow = "\u{001B}[33m"
        public static let blue = "\u{001B}[34m"
        public static let magenta = "\u{001B}[35m"
        public static let cyan = "\u{001B}[36m"

        public static let brightRed = "\u{001B}[91m"
        public static let brightGreen = "\u{001B}[92m"
        public static let brightYellow = "\u{001B}[93m"
        public static let brightBlue = "\u{001B}[94m"
        public static let brightMagenta = "\u{001B}[95m"
        public static let brightCyan = "\u{001B}[96m"

        // Explicit separate colors for User Input, Thinking, Command, Output, Error
        public static let userInput = "\u{001B}[1;93m"  // Bold Bright Yellow for User Input
        public static let thinking  = "\u{001B}[1;95m"  // Bold Bright Magenta for Model Thinking
        public static let command   = "\u{001B}[1;36m"  // Bold Cyan for Command / Execution
        public static let output    = "\u{001B}[1;92m"  // Bold Bright Green for Output to User
        public static let error     = "\u{001B}[1;91m"  // Bold Bright Red for Error Messages
        public static let info      = "\u{001B}[94m"    // Bright Blue for Headers / Info
    }

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

    public static func printUserInput(_ text: String) {
        print("\(Style.userInput)👤 User Task:\(Style.reset) \(Style.userInput)\(text)\(Style.reset)")
    }

    public static func printThinking(_ text: String) {
        print("\(Style.thinking)🧠 Thinking:\(Style.reset) \(Style.thinking)\(text)\(Style.reset)")
    }

    public static func printCommand(_ cmd: String) {
        print("\(Style.command)⚡ Executing (auto-run):\(Style.reset) \(Style.command)\(cmd)\(Style.reset)")
    }

    public static func printTerminalError(_ err: String) {
        print("\(Style.error)✖ Error Output:\(Style.reset)\n\(Style.error)\(err)\(Style.reset)")
    }

    public static func printOutput(_ text: String) {
        print("\(Style.output)💬 Output:\(Style.reset) \(Style.output)\(text)\(Style.reset)")
    }

    public static func info(_ msg: String) {
        print("\(Style.info)ℹ \(msg)\(Style.reset)")
    }

    public static func success(_ msg: String) {
        print("\(Style.output)✔ \(msg)\(Style.reset)")
    }

    public static func warning(_ msg: String) {
        print("\(Style.userInput)▲ \(msg)\(Style.reset)")
    }

    public static func error(_ msg: String) {
        print("\(Style.error)✖ \(msg)\(Style.reset)")
    }

    public static func retryMsg(attempt: Int, maxRetries: Int) {
        print("\(Style.userInput)🔄 Error encountered. Asking Apple FM model to diagnose & fix (attempt \(attempt)/\(maxRetries))...\(Style.reset)")
    }
}
