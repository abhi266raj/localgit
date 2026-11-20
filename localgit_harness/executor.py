"""Safe shell execution and verification of git commands."""

import subprocess
from dataclasses import dataclass
from typing import Optional


@dataclass
class ExecutionResult:
    command: str
    returncode: int
    stdout: str
    stderr: str
    combined_output: str

    @property
    def success(self) -> bool:
        return self.returncode == 0


def is_git_command_safe(command: str) -> bool:
    """Basic validation to ensure the command only uses git and standard chaining."""
    trimmed = command.strip()
    if not trimmed:
        return False

    # Disallow destructive system commands
    forbidden_tokens = ["rm -rf /", "mkfs", "dd if=", ":(){ :|:& };:"]
    for token in forbidden_tokens:
        if token in trimmed:
            return False

    return True


def execute_command(command: str, cwd: Optional[str] = None) -> ExecutionResult:
    """Executes a git command in the shell and captures output."""
    if not is_git_command_safe(command):
        return ExecutionResult(
            command=command,
            returncode=-1,
            stdout="",
            stderr=f"Refusing to execute potentially unsafe command: {command}",
            combined_output="Unsafe command rejected.",
        )

    proc = subprocess.run(
        command,
        shell=True,
        cwd=cwd,
        capture_output=True,
        text=True,
    )

    stdout = proc.stdout.strip()
    stderr = proc.stderr.strip()

    combined_parts = []
    if stdout:
        combined_parts.append(stdout)
    if stderr:
        combined_parts.append(stderr)
    combined = "\n".join(combined_parts)

    return ExecutionResult(
        command=command,
        returncode=proc.returncode,
        stdout=stdout,
        stderr=stderr,
        combined_output=combined,
    )
