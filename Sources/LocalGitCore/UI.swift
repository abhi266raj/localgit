import Foundation

public enum UI {
    public enum Style {
        public static let reset = "\u{001B}[0m"
        public static let bold = "\u{001B}[1m"
        public static let dim = "\u{001B}[2m"
        public static let italic = "\u{001B}[3m"

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
    }

    public static func printBanner() {
        let banner = """
        \(Style.brightCyan)\(Style.bold)
          _                     _  ____ _ _   
         | |    ___   ___ __ _| |/ ___(_) |_ 
         | |   / _ \\ / __/ _` | | |  _| | __|
         | |__| (_) | (_| (_| | | |_| | | |_ 
         |_____\\___/ \\___\\__,_|_|\\____|_|\\__|
        \(Style.reset)\(Style.dim) Local Apple Foundation Model Git Agent in Swift (powered by `fm`)\(Style.reset)
        """
        print(banner)
    }

    public static func info(_ msg: String) {
        print("\(Style.brightBlue)ℹ\(Style.reset) \(msg)")
    }

    public static func success(_ msg: String) {
        print("\(Style.brightGreen)✔\(Style.reset) \(Style.bold)\(msg)\(Style.reset)")
    }

    public static func warning(_ msg: String) {
        print("\(Style.brightYellow)▲\(Style.reset) \(msg)")
    }

    public static func error(_ msg: String) {
        print("\(Style.brightRed)✖\(Style.reset) \(Style.bold)\(msg)\(Style.reset)")
    }

    public static func modelMsg(thought: String, command: String, explanation: String) {
        if !thought.isEmpty {
            print("\(Style.dim)🧠 Analysis: \(thought)\(Style.reset)")
        }
        print("\(Style.brightCyan)🤖 Proposed Command:\(Style.reset) \(Style.bold)\(command)\(Style.reset)")
        if !explanation.isEmpty {
            print("\(Style.dim)   Explanation: \(explanation)\(Style.reset)")
        }
    }

    public static func executingMsg(_ cmd: String) {
        print("\(Style.brightMagenta)⚡ Executing (auto-run):\(Style.reset) \(Style.bold)\(cmd)\(Style.reset)")
    }

    public static func retryMsg(attempt: Int, maxRetries: Int) {
        print("\(Style.brightYellow)🔄 Error encountered. Asking Apple FM model to diagnose & fix (attempt \(attempt)/\(maxRetries))...\(Style.reset)")
    }
}
