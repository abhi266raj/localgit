"""Git repository state and context inspector."""

import subprocess
from dataclasses import dataclass
from typing import Optional


@dataclass
class GitState:
    is_repo: bool
    branch: Optional[str]
    status_summary: str
    recent_logs: str
    remotes: str
    error: Optional[str] = None

    def to_prompt_context(self) -> str:
        if not self.is_repo:
            return "Current Directory: NOT inside a git repository."

        lines = [
            f"Git Repository Context:",
            f"- Current Branch: {self.branch or 'None (detached HEAD or uninitialized)'}",
            f"- Status Summary:\n{self.status_summary.strip() or '  Clean working tree'}",
        ]
        if self.recent_logs.strip():
            lines.append(f"- Recent Commits:\n{self.recent_logs.strip()}")
        else:
            lines.append("- Recent Commits: No commits yet.")

        if self.remotes.strip():
            lines.append(f"- Configured Remotes:\n{self.remotes.strip()}")

        return "\n".join(lines)


def get_git_state(cwd: Optional[str] = None) -> GitState:
    """Inspects the current git repository and returns a structured GitState."""
    try:
        check = subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            cwd=cwd,
            capture_output=True,
            text=True,
        )
        if check.returncode != 0:
            return GitState(
                is_repo=False,
                branch=None,
                status_summary="",
                recent_logs="",
                remotes="",
                error=check.stderr.strip(),
            )

        # Get current branch
        branch_proc = subprocess.run(
            ["git", "branch", "--show-current"],
            cwd=cwd,
            capture_output=True,
            text=True,
        )
        branch = branch_proc.stdout.strip()
        if not branch:
            # Maybe detached or unborn branch
            head_proc = subprocess.run(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=cwd,
                capture_output=True,
                text=True,
            )
            branch = head_proc.stdout.strip() or "main"

        # Get status summary
        status_proc = subprocess.run(
            ["git", "status", "--short", "--branch"],
            cwd=cwd,
            capture_output=True,
            text=True,
        )
        status_summary = status_proc.stdout.strip()

        # Get recent commit logs
        log_proc = subprocess.run(
            ["git", "log", "-n", "3", "--oneline"],
            cwd=cwd,
            capture_output=True,
            text=True,
        )
        recent_logs = log_proc.stdout.strip()

        # Get remotes
        remote_proc = subprocess.run(
            ["git", "remote", "-v"],
            cwd=cwd,
            capture_output=True,
            text=True,
        )
        remotes = remote_proc.stdout.strip()

        return GitState(
            is_repo=True,
            branch=branch,
            status_summary=status_summary,
            recent_logs=recent_logs,
            remotes=remotes,
        )
    except FileNotFoundError:
        return GitState(
            is_repo=False,
            branch=None,
            status_summary="",
            recent_logs="",
            remotes="",
            error="git executable not found in PATH",
        )
