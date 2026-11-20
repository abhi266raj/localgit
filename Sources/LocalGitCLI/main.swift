import Foundation

/// Application Entrypoint for `localgit`.
///
/// Collects command-line arguments (excluding the executable path itself)
/// and dispatches them asynchronously to `CLI.run(args:)`.
let args = Array(CommandLine.arguments.dropFirst())
await CLI.run(args: args)
