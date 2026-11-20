"""Core agent harness orchestrating Apple FM model, command execution, and error recovery."""

from typing import Optional
from .fm_client import AppleFMClient, ModelPlan
from .git_context import get_git_state, GitState
from .executor import execute_command, ExecutionResult
from . import ui


class GitAgentEngine:
    def __init__(
        self,
        fm_client: Optional[AppleFMClient] = None,
        max_retries: int = 3,
        auto_confirm: bool = True,
        verbose: bool = False,
        cwd: Optional[str] = None,
    ):
        self.fm = fm_client or AppleFMClient()
        self.max_retries = max_retries
        self.auto_confirm = auto_confirm
        self.verbose = verbose
        self.cwd = cwd

    def check_prerequisites(self) -> bool:
        """Verifies Apple FM CLI is installed and available."""
        if not self.fm.is_available():
            ui.error(
                "Apple Foundation Models (`fm`) CLI is not available or system model is offline.\n"
                "Ensure macOS 15+ / Apple Intelligence is enabled and `fm available` returns success."
            )
            return False
        return True

    def execute_task(self, task: str) -> bool:
        """Executes a natural language git task with autonomous execution and self-healing error recovery."""
        trimmed_task = task.strip()
        if not trimmed_task:
            return True

        if not self.check_prerequisites():
            return False

        # Step 1: Capture repository context
        git_state = get_git_state(self.cwd)
        if self.verbose:
            ui.info(f"Inspected git state:\n{git_state.to_prompt_context()}")

        # Step 2: Query Apple FM model for proposed git command
        ui.info(f"Consulting Apple Foundation Model for task: {ui.Style.BOLD}'{trimmed_task}'{ui.Style.RESET}...")
        try:
            plan = self.fm.plan_action(trimmed_task, git_state.to_prompt_context())
        except Exception as e:
            ui.error(f"Failed to query Apple Foundation Model: {e}")
            return False

        if not plan.command:
            ui.warning("Model concluded no git command is necessary for this task.")
            if plan.explanation:
                print(f"Explanation: {plan.explanation}")
            return True

        # Display proposed command and thoughts
        ui.model_msg(plan.thought if self.verbose else "", plan.command, plan.explanation)

        # Step 3: Run command (Autonomous / without permission by default)
        current_cmd = plan.command
        if not self.auto_confirm:
            try:
                choice = input(f"{ui.Style.BOLD}Execute this command? [Y/n]: {ui.Style.RESET}").strip().lower()
                if choice not in ("", "y", "yes"):
                    ui.warning("Execution cancelled by user.")
                    return False
            except (KeyboardInterrupt, EOFError):
                print()
                ui.warning("Cancelled.")
                return False

        ui.executing_msg(current_cmd)
        result = execute_command(current_cmd, cwd=self.cwd)

        # Step 4: Handle result / Error recovery loop
        if result.success:
            if result.combined_output:
                print(f"{ui.Style.DIM}{result.combined_output}{ui.Style.RESET}")
            ui.success("Command executed successfully!")
            self._print_post_state()
            return True

        # Failure occurred
        ui.error(f"Command exited with code {result.returncode}")
        if result.combined_output:
            print(f"{ui.Style.BRIGHT_RED}{result.combined_output}{ui.Style.RESET}")

        # Recovery loop: Feed error back to Apple FM model to diagnose & verify
        last_failed_cmd = current_cmd
        last_result = result

        for attempt in range(1, self.max_retries + 1):
            ui.retry_msg(attempt, self.max_retries)
            updated_state = get_git_state(self.cwd)

            try:
                recovery_plan = self.fm.plan_recovery(
                    task=trimmed_task,
                    failed_command=last_failed_cmd,
                    exit_code=last_result.returncode,
                    output=last_result.combined_output,
                    git_context=updated_state.to_prompt_context(),
                )
            except Exception as e:
                ui.error(f"Failed to query model for error recovery: {e}")
                return False

            if not recovery_plan.command:
                ui.error("Model could not determine a recovery command.")
                if recovery_plan.explanation:
                    print(f"Model note: {recovery_plan.explanation}")
                return False

            ui.model_msg(
                recovery_plan.thought if self.verbose else "",
                recovery_plan.command,
                recovery_plan.explanation,
            )

            if not self.auto_confirm:
                try:
                    choice = input(f"{ui.Style.BOLD}Execute fix command? [Y/n]: {ui.Style.RESET}").strip().lower()
                    if choice not in ("", "y", "yes"):
                        ui.warning("Recovery cancelled by user.")
                        return False
                except (KeyboardInterrupt, EOFError):
                    print()
                    ui.warning("Cancelled.")
                    return False

            ui.executing_msg(recovery_plan.command)
            last_failed_cmd = recovery_plan.command
            last_result = execute_command(recovery_plan.command, cwd=self.cwd)

            if last_result.success:
                if last_result.combined_output:
                    print(f"{ui.Style.DIM}{last_result.combined_output}{ui.Style.RESET}")
                ui.success(f"Recovery successful on attempt {attempt}! Goal achieved.")
                self._print_post_state()
                return True

            ui.error(f"Fix command failed with code {last_result.returncode}")
            if last_result.combined_output:
                print(f"{ui.Style.BRIGHT_RED}{last_result.combined_output}{ui.Style.RESET}")

        ui.error(f"Reached maximum retries ({self.max_retries}). Task could not be automatically resolved.")
        return False

    def _print_post_state(self):
        state = get_git_state(self.cwd)
        if state.is_repo:
            branch_info = f"branch: {state.branch}" if state.branch else "no branch"
            status_lines = state.status_summary.splitlines()
            short_status = status_lines[0] if status_lines else "clean"
            print(f"{ui.Style.DIM}↳ Current state: [{branch_info}] {short_status}{ui.Style.RESET}\n")
