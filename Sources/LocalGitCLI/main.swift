import Foundation

let args = Array(CommandLine.arguments.dropFirst())
await CLI.run(args: args)
