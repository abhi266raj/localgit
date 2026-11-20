# LocalGit 🤖🍏 (Swift & Xcode)

> **Autonomous Git Agent Harness in Swift, Powered by Local Apple Foundation Models (`fm`)**

`LocalGit` is a native Swift CLI harness and Xcode project that turns natural language intent into executed, verified Git actions. Powered by Apple's on-device Foundation Models (`fm`), it autonomously plans, executes, diagnoses errors, and self-heals without sending any code or prompts to external cloud APIs.

---

## 🌐 The Server-Connected Architecture: How the Server Does All the Work

`LocalGit` is built on a client-server architecture where **the local Apple Foundation Model acts as the intelligent backend server**, while the Swift CLI operates as a lightweight terminal harness.

```mermaid
sequenceDiagram
    autonumber
    actor User as 👤 Developer
    participant Client as 🖥️ LocalGit CLI (Swift Harness)
    participant Server as 🍏 Local FM Server (Apple Foundation Model)
    participant Terminal as 💻 Shell / Git

    User->>Client: "stage all changes and commit with feat: login"
    Note over Client: In Yellow: User Input
    Client->>Client: Inspect Git state (branch, status, logs)
    
    rect rgb(30, 20, 40)
        Note over Client,Server: Step 1: Action Planning (Server-Side)
        Client->>Server: Task + Git Context (+ Session History if enabled)
        Server-->>Client: Plan: { thought, command, explanation }
    end
    
    Note over Client: In Magenta: Model Thinking<br/>In Cyan: Executing Command
    Client->>Terminal: Execute `git add . && git commit -m "feat: login"`
    
    alt Command Succeeded
        Terminal-->>Client: Raw output (e.g. `[main abc1234] feat: login...`)
        rect rgb(20, 35, 25)
            Note over Client,Server: Step 2: Output Synthesis (Server-Side)
            Client->>Server: Task + Executed Command + Raw Terminal Output
            Server-->>Client: Synthesized user-friendly output
        end
        Note over Client: In Green: Synthesized Output
        Client->>User: "Your changes were staged and committed with 'feat: login'!"
    else Command Encountered an Error
        Terminal-->>Client: Exit code != 0, stderr (e.g. conflict, detached HEAD)
        Note over Client: In Red: Terminal Error Output
        rect rgb(40, 20, 20)
            Note over Client,Server: Self-Healing Error Recovery (Server-Side)
            Client->>Server: Task + Failed Command + Error Output + State
            Server-->>Client: Diagnostic Thought + Corrected Command
        end
        Note over Client: In Magenta: Diagnosis Thought<br/>In Cyan: Executing Fix
        Client->>Terminal: Execute Corrected Command
        Terminal-->>Client: Success Output
        Client->>Server: Synthesize final output
        Server-->>Client: User-friendly resolution summary
        Note over Client: In Green: Synthesized Output
        Client->>User: "Conflict resolved and commit finalized successfully."
    end
```

### Why the Server-Connected Model?
- **Cognitive Offloading**: The CLI contains zero hardcoded Git syntax rules. 100% of decision making, diagnosis, and command generation happens on the Foundation Model server.
- **Dual Server Modes**:
  1. **Persistent Server (`fm serve`)**: Run `fm serve --port 1976`. The server keeps the model resident in Apple Neural Engine / Unified Memory, providing ultra-low latency OpenAI-compatible completions at `http://127.0.0.1:1976/v1/chat/completions`.
  2. **Direct CLI Daemon**: If the background server is offline, `LocalGit` automatically falls back to `/usr/bin/fm respond`, requiring no manual server configuration.
- **Two-Step Execution Workflow**:
  - **Step 1**: The server plans the exact Git command sequence.
  - **Step 2**: The server synthesizes the raw terminal output into a friendly, clear summary to present to the user.

---

## 📦 How Swift Code Becomes the `localgit` Command (and Part of Your Shell)

Many developers wonder: *“How does a folder with Swift files actually compile into a command called `localgit` and become a permanent part of my shell environment?”*

Here is the exact anatomy of how `LocalGit` is declared, compiled into a named binary, and integrated into your terminal's `$PATH`:

```mermaid
flowchart TD
    subgraph Step1["1. Defining the Command Name"]
        Package["Package.swift / project.yml"] --> DefineProduct[".executable(name: 'localgit')\ntype: tool, PRODUCT_NAME: localgit"]
    end

    subgraph Step2["2. Compiling the Binary"]
        DefineProduct --> SwiftBuild["swift build -c debug / release"]
        SwiftBuild --> OutputBinary[".build/debug/localgit\n(Compiled ARM64 Mach-O Binary)"]
    end

    subgraph Step3["3. Making It Part of Your Shell ($PATH)"]
        OutputBinary --> LauncherScript["localgit (Launcher in Repo Root)"]
        LauncherScript --> Symlink["Symlink into ~/.local/bin/localgit"]
        Symlink --> ShellPATH["$PATH Lookup (/Users/abhiraj/.local/bin)"]
    end

    subgraph Step4["4. Terminal Invocation & Auto-Rebuild"]
        UserRuns["User runs: 'localgit' anywhere in terminal"] --> ShellPATH
        ShellPATH --> CheckTimestamp{"Any file in Sources/ newer than binary?"}
        CheckTimestamp -- "Code Changed" --> Rebuild["Auto-runs 'swift build'"]
        CheckTimestamp -- "No Changes" --> ExecDirect["Immediate Execution"]
        Rebuild --> ExecDirect
        ExecDirect --> RunInPWD["Runs inside caller's current directory ($PWD)"]
    end
```

### 1. Declaring the Binary in `Package.swift` and Xcode
The command name `localgit` is not arbitrary; it is explicitly defined as an executable product in `Package.swift`:
```swift
products: [
    // Declares that building this package produces an executable named 'localgit'
    .executable(name: "localgit", targets: ["LocalGitCLI"])
],
targets: [
    .target(name: "LocalGitCore", path: "Sources/LocalGitCore"),
    .executableTarget(name: "LocalGitCLI", dependencies: ["LocalGitCore"], path: "Sources/LocalGitCLI")
]
```
Similarly, in `project.yml` for Xcode:
```yaml
targets:
  localgit:
    type: tool
    platform: macOS
    settings:
      PRODUCT_NAME: localgit
```
When `swift build` runs, SwiftPM compiles all code in `Sources/LocalGitCore` and `Sources/LocalGitCLI` and emits an executable file named `localgit` in `.build/debug/localgit`.

### 2. How the Command Becomes Part of Your Shell (`$PATH`)
When you type a command in terminal (like `git`, `ls`, or `localgit`), your shell (`bash` or `zsh`) does not search the entire disk. It looks through directories listed in the `$PATH` environment variable:
```bash
$ echo $PATH
/Users/abhiraj/.local/bin:/usr/local/bin:/usr/bin:/bin:...
```
To make `localgit` accessible globally as a first-class shell command:
```bash
ln -sf /Users/abhiraj/Documents/harness/localgit ~/.local/bin/localgit
```
Because `~/.local/bin` is in `$PATH`, the shell instantly recognizes `localgit` as a native system command from any directory.

### 3. The Auto-Compilation Bridge ([localgit](file:///Users/abhiraj/Documents/harness/localgit))
The script at `localgit` connects the user's terminal to the compiled Swift binary and automates rebuilds:
```bash
#!/bin/bash
set -e

# 1. Resolve physical path even through symlinks (~/.local/bin/localgit -> harness/localgit)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
PROJECT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

BIN="$PROJECT_DIR/.build/debug/localgit"

# 2. Check if Swift source files have changed since the last compilation
if [ ! -f "$BIN" ] || [ -n "$(find "$PROJECT_DIR/Sources" -newer "$BIN" 2>/dev/null)" ]; then
    (cd "$PROJECT_DIR" && swift build -c debug >/dev/null)
fi

# 3. Hand over execution to the compiled Mach-O binary in the caller's current directory
exec "$BIN" "$@"
```

### 4. What Happens When You Type `localgit` in Any Folder?
1. **Lookup**: You run `localgit "create branch dev"`. The shell looks in `$PATH` and finds `~/.local/bin/localgit`.
2. **Symlink Resolution**: The script resolves the symlink to find the real project directory (`/Users/abhiraj/Documents/harness`).
3. **Freshness Check**: It compares modification dates. If you just edited `Sources/LocalGitCore/AgentEngine.swift`, it automatically triggers `swift build` so your changes take effect immediately.
4. **Context Preservation**: `exec "$BIN" "$@"` replaces the shell process with the compiled Swift binary while keeping the **caller's `$PWD` (current working directory)**. This ensures `localgit` inspects and acts on the repository you are currently working in!

---

## 🔬 Under the Hood: How Swift Code Executes Terminal Commands

This section explains the exact engineering mechanisms that bridge the high-level Swift codebase down to native terminal commands and process management.

```mermaid
flowchart TD
    subgraph UserSpace["Terminal / User Interaction"]
        CLI_Input["User Input: 'undo last commit'"] --> Launcher["localgit (Bash Launcher)"]
    end

    subgraph BuildPipeline["Compilation & Binary Execution"]
        Launcher --> CheckBuild{"Sources newer than .build/debug/localgit?"}
        CheckBuild -- Yes --> Recompile["swift build -c debug"]
        CheckBuild -- No --> Binary["Execute Mach-O Binary (.build/debug/localgit)"]
        Recompile --> Binary
    end

    subgraph SwiftCore["LocalGit Swift Core Engine"]
        Binary --> CLI_Parser["CLI.swift: Argument Parsing / REPL Loop"]
        CLI_Parser --> Engine["AgentEngine.swift: Lifecycle Coordinator"]
        Engine --> Inspector["GitContextInspector (Process: git status/branch/log)"]
        Engine --> ModelClient["AppleFMClient: HTTP (fm serve) or Process (/usr/bin/fm)"]
        Engine --> Executor["CommandExecutor.swift: Safe Shell Execution"]
    end

    subgraph OS_Execution["macOS Kernel & Shell Subprocesses"]
        Executor --> ForkExec["Process(): /bin/zsh -c '<git command>'"]
        ForkExec --> Pipes["Standard Output & Error Pipes (FileHandle reading)"]
        Pipes --> ExitCode["terminationStatus (0 = Success, >0 = Error)"]
    end

    ExitCode --> Engine
```

### How Swift Executes Terminal Commands (`Foundation.Process`)
In `Sources/LocalGitCore/Executor.swift`, Swift does not use slow or unsafe C `system()` calls. Instead, it uses **`Foundation.Process`** and Unix anonymous pipes:

```swift
public static func execute(command: String, cwd: String? = nil) -> ExecutionResult {
    // 1. Instantiate the Process object
    let process = Process()
    
    // 2. Set the executable binary to the user shell
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]

    // 3. Set the current working directory to the target git repo
    if let cwd = cwd {
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    }

    // 4. Attach anonymous pipes for standard output and error
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    // 5. Spawn the subprocess and wait for completion
    try process.run()
    process.waitUntilExit()

    // 6. Read stream data from file handles into Swift strings
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    let stdout = String(data: outData, encoding: .utf8) ?? ""
    let stderr = String(data: errData, encoding: .utf8) ?? ""

    // 7. Check kernel exit status
    return ExecutionResult(
        command: command,
        exitCode: process.terminationStatus,
        stdout: stdout,
        stderr: stderr,
        combinedOutput: stdout + stderr
    )
}
```

### How Swift Communicates with the Apple Foundation Model
The client communicates with Apple Foundation Models using two distinct pathways in `Sources/LocalGitCore/FMClient.swift`:

#### Pathway A: HTTP Client to `fm serve` (`URLSession`)
When the server is active, Swift sends asynchronous HTTP POST requests to `http://127.0.0.1:1976/v1/chat/completions`:
```swift
var request = URLRequest(url: URL(string: "http://127.0.0.1:1976/v1/chat/completions")!)
request.httpMethod = "POST"
request.addValue("application/json", forHTTPHeaderField: "Content-Type")

let body: [String: Any] = [
    "model": "system",
    "stream": false,
    "messages": [
        ["role": "system", "content": systemPrompt],
        ["role": "user", "content": userPrompt]
    ]
]
request.httpBody = try JSONSerialization.data(withJSONObject: body)
```

#### Pathway B: Inter-Process Communication (IPC via `/usr/bin/fm respond`)
If the HTTP server is not running, Swift spawns `/usr/bin/fm` with strict JSON schema constraints:
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/fm")
process.arguments = [
    "respond",
    "--no-stream",
    "--schema", schemaFilePath,
    "-i", systemInstructions,
    prompt
]
```
The output is captured through `Pipe` and decoded with `JSONDecoder` into a strongly-typed `GitPlan(thought: String, command: String, explanation: String)`.

### How the Bash Launcher (`localgit`) Integrates with the System
The wrapper script in `localgit` enables system-wide accessibility:
1. **Resolves Real Path**: Uses `readlink` to resolve symlinks if invoked from `~/.local/bin/localgit`.
2. **Auto-Compiles on Code Edits**: Runs `find Sources -newer .build/debug/localgit`. If any Swift source file was modified, it recompiles with `swift build` before running.
3. **Preserves Environment & Context**: Uses `exec "$BIN" "$@"` so process IDs, working directories (`$PWD`), and terminal pipes are passed directly to the Swift binary.

---

## 🎨 Visual Color Hierarchy

`LocalGit` strictly formats every stage in dedicated ANSI colors:
- 👤 **User Task** (`Bright Yellow`): The user's goal or prompt.
- 🧠 **Model Thinking** (`Bright Magenta`): The model's reasoning and diagnosis before executing.
- ⚡ **Command Execution** (`Cyan`): The shell command being executed.
- ✖ **Terminal Error** (`Bright Red`): Raw error output when a command fails.
- 💬 **Synthesized Output** (`Bright Green`): The clean, final output synthesized by the model.

---

## 🧹 Session History & Clean State Management

- **Default Mode (Clean Slate)**: Local models perform best without context pollution. Once a task completes, **task history is automatically cleared** (`clearHistory()`).
- **Persistent History (`-H` / `--with-history`)**: When launched with `-H`, prior completed tasks and executed commands in the session are preserved and sent to the server for multi-task continuity.

---

## 🚀 Running & Global Installation

### 1. One-Step Installation via Script
Install `localgit` to your user `$PATH` (`~/.local/bin/localgit`):
```bash
# Using the installer script:
./install.sh

# Or using Makefile:
make install
```

### 2. From Any Directory in Bash
Once installed, `localgit` works in any terminal, directory, or Bash script:
```bash
localgit "create branch feature-x and switch to it"

# Interactive REPL:
localgit
```

### 2. Auto-Build on Source Changes
The wrapper script in `localgit` automatically detects if any files in `Sources/` have changed and recompiles with `swift build` before running, ensuring you are always running the latest version.

### 3. Open in Xcode
```bash
open LocalGit.xcodeproj
```
Select the `localgit` scheme and press **Cmd + R** to run or debug.

### 4. Optional: Start Persistent Server for Max Speed
```bash
fm serve --port 1976
```
`LocalGit` will automatically detect the server and route completions over local HTTP for near-instant responses.

---

## 🧪 Testing

Run the test suite covering execution, context extraction, schema parsing, and self-healing recovery:
```bash
swift test
```

---

## 📂 Project Structure

```
localgit/
├── LocalGit.xcodeproj        # Native Xcode project
├── project.yml               # XcodeGen specification
├── Package.swift             # Swift Package Manager manifest
├── Makefile                  # Build, test, and install targets
├── install.sh                # 1-step installer to user $PATH
├── localgit                  # Global bash launcher script (auto-recompiles)
├── README.md                 # Documentation and architecture
├── .gitignore                # Git ignore rules
├── Tests/
│   └── LocalGitTests/
│       └── LocalGitTests.swift # XCTest unit tests
└── Sources/
    ├── LocalGitCore/
    │   ├── AgentEngine.swift # Autonomous agent loop & error recovery
    │   ├── FMClient.swift    # Dual-mode Apple FM Client (HTTP Server + CLI)
    │   ├── GitContext.swift  # Repository state inspector
    │   ├── Executor.swift    # Safe command executor
    │   └── UI.swift          # Visual color formatting
    └── LocalGitCLI/
        ├── CLI.swift         # REPL & argument parser
        └── main.swift        # Executable entrypoint
```
