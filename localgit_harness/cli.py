"""Command Line Interface and Interactive REPL for LocalGit."""

import argparse
import os
import sys

# Optional readline for arrow key navigation & command history in REPL
try:
    import readline
except ImportError:
    pass

from . import ui
from .engine import GitAgentEngine
from .git_context import get_git_state


def repl(engine: GitAgentEngine):
    """Interactive agent loop."""
    ui.print_banner()

    state = get_git_state(engine.cwd)
    if not state.is_repo:
        ui.warning("Current directory is not a Git repository. You can say 'initialize git repository' to start.")

    print(f"{ui.Style.DIM}Type your task in plain English (e.g. 'stage all files and commit with feat: initial commit').")
    print(f"Commands: 'status' (view git status), 'help', 'exit' or 'quit' to leave.{ui.Style.RESET}\n")

    history_file = os.path.expanduser("~/.localgit_history")
    try:
        if os.path.exists(history_file):
            readline.read_history_file(history_file)
    except Exception:
        pass

    try:
        while True:
            cur_state = get_git_state(engine.cwd)
            branch_str = cur_state.branch if (cur_state.is_repo and cur_state.branch) else "no-repo"
            prompt_str = f"{ui.Style.BRIGHT_GREEN}localgit{ui.Style.RESET} ({ui.Style.BRIGHT_CYAN}{branch_str}{ui.Style.RESET}) > "

            try:
                user_input = input(prompt_str).strip()
            except (KeyboardInterrupt, EOFError):
                print("\nGoodbye!")
                break

            if not user_input:
                continue

            if user_input.lower() in ("exit", "quit", "q"):
                print("Goodbye!")
                break

            if user_input.lower() in ("help", "?"):
                print(f"""
{ui.Style.BOLD}LocalGit Help:{ui.Style.RESET}
  Simply type what you want to do with Git in plain English!
  Examples:
    - "undo my last commit and keep changes staged"
    - "create a new branch named bugfix/auth and switch to it"
    - "stage everything and commit with message 'fix: login issue'"
    - "stash all current uncommitted changes"
    - "show last 5 commits with graphs"
  
  Special Commands:
    - {ui.Style.CYAN}status{ui.Style.RESET} : Show detailed git status
    - {ui.Style.CYAN}help{ui.Style.RESET}   : Show this help text
    - {ui.Style.CYAN}exit{ui.Style.RESET}   : Exit the agent
""")
                continue

            if user_input.lower() == "status":
                s = get_git_state(engine.cwd)
                print(f"\n{s.to_prompt_context()}\n")
                continue

            # Execute task through agent engine
            engine.execute_task(user_input)

    finally:
        try:
            readline.write_history_file(history_file)
        except Exception:
            pass


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="localgit",
        description="Autonomous Git agent harness powered by local Apple Foundation Models (`fm`).",
    )
    parser.add_argument(
        "task",
        nargs="*",
        help="Natural language Git task to execute. If omitted, opens interactive agent session.",
    )
    parser.add_argument(
        "-a",
        "--ask",
        action="store_true",
        help="Ask for confirmation before executing commands (default: run without permission).",
    )
    parser.add_argument(
        "-r",
        "--max-retries",
        type=int,
        default=3,
        help="Maximum self-healing recovery attempts upon error (default: 3).",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Display detailed model reasoning and context.",
    )
    parser.add_argument(
        "-C",
        "--cwd",
        type=str,
        default=None,
        help="Target git repository directory path.",
    )

    args = parser.parse_args(argv)

    auto_confirm = not args.ask

    engine = GitAgentEngine(
        max_retries=args.max_retries,
        auto_confirm=auto_confirm,
        verbose=args.verbose,
        cwd=args.cwd,
    )

    if args.task:
        task_str = " ".join(args.task)
        success = engine.execute_task(task_str)
        sys.exit(0 if success else 1)
    else:
        repl(engine)


if __name__ == "__main__":
    main()
