# LocalGit 🤖🍏 (Swift & Xcode)

> **Autonomous Git Agent Harness Written in Swift, Powered by Local Apple Foundation Models (`fm`)**

`LocalGit` is a native Swift CLI harness and Xcode project that turns natural language intent into executed, verified Git actions. Powered by Apple's on-device Foundation Models (`fm` CLI), it autonomously plans, executes, diagnoses errors, and self-heals without sending any code or prompts to the cloud.

---

## 🌟 Key Features

- **100% Native Swift & Xcode Project**: Complete Swift architecture with `LocalGitCore`, `localgit` CLI target, and `LocalGitTests` unit tests. Fully compatible with both **Xcode** (`LocalGit.xcodeproj`) and **Swift Package Manager** (`Package.swift`).
- **On-Device Apple Foundation Model**: Uses macOS's built-in Foundation Models (`/usr/bin/fm`). Zero cloud latency, zero external API keys, 100% private.
- **Autonomous Execution**: By default, commands are executed immediately without prompting for permission.
- **Self-Healing Error Recovery**: If a Git command fails (e.g., branch already exists, merge conflict, untracked changes, detached HEAD), `LocalGit` captures the exit code and `stderr`, hands it back to the Apple Foundation Model for diagnosis, and automatically executes the fix.
- **Context-Aware**: Inspects branch names, recent commit logs, working tree status (`git status --short`), and remotes to ground the model.
- **Interactive REPL & CLI**: Run as an interactive shell (`localgit`) with prompt or as a single-command one-liner.

---

## 🏗️ Architecture

```mermaid
flowchart TD
    User([User Prompt / Task]) --> CLI[CLI / Interactive REPL]
    CLI --> Harness[GitAgentEngine (Swift)]
    Harness --> Inspector[GitContextInspector]
    Inspector --> Context[(Branch, Status, Logs, Remotes)]
    Context --> FM[AppleFMClient\n/usr/bin/fm respond]
    FM --> JSON[Structured GitPlan\ncommand + explanation]
    JSON --> Exec[CommandExecutor (Swift Process)]
    Exec --> Run[Execute Git Command]
    Run --> Success{Exit Code 0?}
    Success -- Yes --> Done([✔ Success & State Summary])
    Success -- No --> ErrorCapture[Capture Stderr & Code]
    ErrorCapture --> Retries{Attempts < Max?}
    Retries -- Yes --> FM_Heal[Apple FM Error Recovery\nDiagnose & Fix]
    FM_Heal --> JSON
    Retries -- No --> Fail([✖ Report Unresolved Error])
```

---

## 🛠️ Xcode & Swift Package Structure

The repository contains:
- **`LocalGit.xcodeproj`**: Full Xcode project for opening, editing, running, and debugging in Xcode.
- **`project.yml`**: XcodeGen project spec used to generate and maintain `LocalGit.xcodeproj`.
- **`Package.swift`**: Swift Package Manager manifest with library, executable, and test targets.
- **`Sources/LocalGitCore/`**:
  - `FMClient.swift`: Interface to Apple Foundation Models with schema validation and error recovery prompts.
  - `GitContext.swift`: Git repository state inspector.
  - `Executor.swift`: Command execution and safety filtering.
  - `AgentEngine.swift`: Agent harness loop and self-healing error verification.
  - `UI.swift`: ANSI color formatting and status messaging.
- **`Sources/LocalGitCLI/`**:
  - `main.swift`: Entry point.
  - `CLI.swift`: Argument parser and interactive REPL.
- **`Tests/LocalGitTests/`**:
  - `LocalGitTests.swift`: Comprehensive unit tests.
- **`localgit`**: Executable launcher for the compiled Swift binary.

---

## 🚀 Building & Running

### 1. In Xcode
Open the project in Xcode:
```bash
open LocalGit.xcodeproj
```
Select the `localgit` scheme, set any arguments if desired in **Product > Scheme > Edit Scheme...**, and press **Cmd + R** to run.

### 2. From Terminal via CLI Launcher
```bash
# Interactive REPL session
./localgit

# Single-shot command (executes without permission)
./localgit "create branch feature-auth and switch to it"
```

### 3. Using Swift Package Manager
```bash
# Build
swift build

# Run
swift run localgit "show current status"

# Run tests
swift test
```

### 4. Install Globally
```bash
# Install to ~/.local/bin
mkdir -p ~/.local/bin
swift build -c release
cp .build/release/localgit ~/.local/bin/localgit
```

---

## 💻 Usage & Options

```
Usage: localgit [options] [task...]

Options:
  -a, --ask             Ask for confirmation before executing commands (default: run without permission)
  -r, --max-retries <n> Max self-healing recovery attempts upon error (default: 3)
  -v, --verbose         Print detailed model reasoning and context
  -C, --cwd <path>      Target directory of git repository
  -h, --help            Show this help information
```

### Interactive REPL Session Example
```
$ ./localgit

  _                     _  ____ _ _   
 | |    ___   ___ __ _| |/ ___(_) |_ 
 | |   / _ \ / __/ _` | | |  _| | __|
 | |__| (_) | (_| (_| | | |_| | | |_ 
 |_____\___/ \___\__,_|_|\____|_|\__|
 Local Apple Foundation Model Git Agent in Swift (powered by `fm`)

localgit (main) > stage all files and commit with feat: native swift harness
ℹ Consulting Apple Foundation Model for task: 'stage all files and commit with feat: native swift harness'...
🤖 Proposed Command: git add . && git commit -m "feat: native swift harness"
   Explanation: Stages all changes and commits them with the given commit message.
⚡ Executing (auto-run): git add . && git commit -m "feat: native swift harness"
✔ Command executed successfully!
↳ Current state: [branch: main] clean

localgit (main) > exit
```

---

## 🔄 Self-Healing Error Recovery Flow

When a command fails (e.g. branch conflicts, missing remotes, detached HEAD):
1. `LocalGit` captures the exit code and `stderr` output.
2. It sends the failure diagnosis back to the Apple Foundation Model along with the original user goal and updated git context.
3. The model returns the corrected command.
4. `LocalGit` executes the fix automatically, verifying up to `--max-retries` times until success.
