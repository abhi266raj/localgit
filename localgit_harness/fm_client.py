"""Interface to Apple Foundation Models CLI (`fm`)."""

import json
import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from typing import Optional


@dataclass
class ModelPlan:
    thought: str
    command: str
    explanation: str
    raw_response: str


SYSTEM_INSTRUCTIONS = """You are an expert autonomous Git engineering agent.
Your mission is to translate user goals or errors into exact, correct Git commands.

Rules:
1. The 'command' field MUST contain the exact command to run in the terminal (e.g., 'git add . && git commit -m "feat: add login"').
2. Chain multiple commands with '&&' if multiple steps are needed.
3. Every command must invoke 'git' or safe shell utilities needed for git operations.
4. If the task is already satisfied or cannot be done, explain in 'thought' and 'explanation' and set command to '' (empty string).
5. For error recovery: diagnose the root cause carefully (e.g. untracked conflicts, detached HEAD, missing upstream, existing branch) and generate the precise fix.
"""


class AppleFMClient:
    def __init__(self, binary_path: Optional[str] = None):
        self.binary_path = binary_path or shutil.which("fm") or "/usr/bin/fm"
        self._schema_file: Optional[str] = None

    def is_available(self) -> bool:
        """Checks if fm is installed and the system model is available."""
        if not os.path.exists(self.binary_path):
            return False
        try:
            res = subprocess.run(
                [self.binary_path, "available"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            return res.returncode == 0 and "System model available" in res.stdout
        except Exception:
            return False

    def _ensure_schema(self) -> str:
        """Generates and returns the path to the structured JSON schema file."""
        if self._schema_file and os.path.exists(self._schema_file):
            return self._schema_file

        schema_dict = {
            "title": "GitPlan",
            "type": "object",
            "required": ["thought", "command", "explanation"],
            "additionalProperties": False,
            "properties": {
                "thought": {
                    "type": "string",
                    "description": "Analysis of the repository state and strategy",
                },
                "command": {
                    "type": "string",
                    "description": "Exact git command(s) to execute in shell",
                },
                "explanation": {
                    "type": "string",
                    "description": "User-friendly explanation of what the command does",
                },
            },
            "x-order": ["thought", "command", "explanation"],
        }

        # Write to a persistent temp file
        temp_dir = os.path.join(tempfile.gettempdir(), "localgit")
        os.makedirs(temp_dir, exist_ok=True)
        schema_path = os.path.join(temp_dir, "git_plan_schema.json")
        with open(schema_path, "w", encoding="utf-8") as f:
            json.dump(schema_dict, f, indent=2)

        self._schema_file = schema_path
        return schema_path

    def _parse_response(self, raw_text: str) -> ModelPlan:
        """Parses model response into ModelPlan, handling raw json or code blocks."""
        cleaned = raw_text.strip()
        # Check for json code block ```json ... ```
        code_block = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", cleaned, re.DOTALL)
        if code_block:
            cleaned = code_block.group(1).strip()
        else:
            # Check for naked JSON object
            naked_json = re.search(r"(\{.*\})", cleaned, re.DOTALL)
            if naked_json:
                cleaned = naked_json.group(1).strip()

        try:
            data = json.loads(cleaned)
            return ModelPlan(
                thought=data.get("thought", "").strip(),
                command=data.get("command", "").strip(),
                explanation=data.get("explanation", "").strip(),
                raw_response=raw_text,
            )
        except Exception:
            # Fallback heuristic: check if raw text is a git command itself
            lines = [l.strip() for l in raw_text.splitlines() if l.strip()]
            git_lines = [l for l in lines if l.startswith("git ") or "git " in l]
            cmd = git_lines[0] if git_lines else ""
            return ModelPlan(
                thought="Direct command extraction fallback",
                command=cmd,
                explanation="Extracted command directly from model response",
                raw_response=raw_text,
            )

    def plan_action(self, task: str, git_context: str) -> ModelPlan:
        """Asks the model to generate a git command for the given task and context."""
        schema_path = self._ensure_schema()
        prompt = f"""Repository State:
{git_context}

User Task:
{task}

Provide the exact git command to execute."""

        cmd = [
            self.binary_path,
            "respond",
            "--no-stream",
            "--schema",
            schema_path,
            "-i",
            SYSTEM_INSTRUCTIONS,
            prompt,
        ]

        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"Apple FM command failed: {res.stderr.strip()}")

        return self._parse_response(res.stdout)

    def plan_recovery(
        self,
        task: str,
        failed_command: str,
        exit_code: int,
        output: str,
        git_context: str,
    ) -> ModelPlan:
        """Asks the model to diagnose an error and provide a corrected command."""
        schema_path = self._ensure_schema()
        prompt = f"""An error occurred while attempting to satisfy the user goal.

User Goal:
{task}

Previous Command Attempted:
{failed_command}

Exit Code:
{exit_code}

Terminal Output / Error:
{output.strip() or '(no output)'}

Updated Repository State:
{git_context}

Diagnose the exact root cause of this failure and provide the corrected git command to fix the issue and achieve the goal."""

        cmd = [
            self.binary_path,
            "respond",
            "--no-stream",
            "--schema",
            schema_path,
            "-i",
            SYSTEM_INSTRUCTIONS,
            prompt,
        ]

        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"Apple FM command failed during recovery: {res.stderr.strip()}")

        return self._parse_response(res.stdout)
