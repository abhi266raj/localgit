"""Tests for LocalGit harness components."""

import unittest
from unittest.mock import MagicMock, patch
import os
import sys

# Ensure root dir is in path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from localgit_harness.git_context import GitState, get_git_state
from localgit_harness.executor import is_git_command_safe, execute_command, ExecutionResult
from localgit_harness.fm_client import AppleFMClient, ModelPlan
from localgit_harness.engine import GitAgentEngine


class TestGitContext(unittest.TestCase):
    def test_git_state_prompt_context(self):
        state = GitState(
            is_repo=True,
            branch="main",
            status_summary=" M README.md",
            recent_logs="a1b2c3d initial commit",
            remotes="origin git@github.com:user/repo.git (fetch)",
        )
        context = state.to_prompt_context()
        self.assertIn("Current Branch: main", context)
        self.assertIn("M README.md", context)
        self.assertIn("a1b2c3d initial commit", context)

    def test_not_a_repo(self):
        state = GitState(
            is_repo=False,
            branch=None,
            status_summary="",
            recent_logs="",
            remotes="",
        )
        context = state.to_prompt_context()
        self.assertIn("NOT inside a git repository", context)


class TestExecutor(unittest.TestCase):
    def test_safety_check(self):
        self.assertTrue(is_git_command_safe("git status"))
        self.assertTrue(is_git_command_safe("git add . && git commit -m 'test'"))
        self.assertFalse(is_git_command_safe("rm -rf /"))
        self.assertFalse(is_git_command_safe(""))

    def test_execute_echo(self):
        result = execute_command("echo 'hello localgit'")
        self.assertTrue(result.success)
        self.assertEqual(result.stdout, "hello localgit")
        self.assertEqual(result.returncode, 0)


class TestFMClientParsing(unittest.TestCase):
    def setUp(self):
        self.client = AppleFMClient(binary_path="/usr/bin/fm")

    def test_parse_clean_json(self):
        raw = '{"thought": "Need to stage", "command": "git add .", "explanation": "Stage all files"}'
        plan = self.client._parse_response(raw)
        self.assertEqual(plan.thought, "Need to stage")
        self.assertEqual(plan.command, "git add .")
        self.assertEqual(plan.explanation, "Stage all files")

    def test_parse_markdown_codeblock(self):
        raw = """Here is the plan:
```json
{
  "thought": "Create feature branch",
  "command": "git checkout -b feature-test",
  "explanation": "Create and switch to feature-test"
}
```
Done!"""
        plan = self.client._parse_response(raw)
        self.assertEqual(plan.command, "git checkout -b feature-test")
        self.assertEqual(plan.explanation, "Create and switch to feature-test")


class TestAgentEngine(unittest.TestCase):
    def test_successful_execution_without_permission(self):
        mock_fm = MagicMock(spec=AppleFMClient)
        mock_fm.is_available.return_value = True
        mock_fm.plan_action.return_value = ModelPlan(
            thought="Check status",
            command="echo 'mock git success'",
            explanation="Mock command that succeeds",
            raw_response="",
        )

        engine = GitAgentEngine(
            fm_client=mock_fm,
            max_retries=2,
            auto_confirm=True,  # Run without permission
        )

        success = engine.execute_task("check repo status")
        self.assertTrue(success)
        mock_fm.plan_action.assert_called_once()
        mock_fm.plan_recovery.assert_not_called()

    def test_error_recovery_flow(self):
        mock_fm = MagicMock(spec=AppleFMClient)
        mock_fm.is_available.return_value = True
        
        # First plan produces a failing command
        mock_fm.plan_action.return_value = ModelPlan(
            thought="Try initial command",
            command="sh -c 'echo \"fatal: error\" >&2 && exit 1'",
            explanation="Failing command",
            raw_response="",
        )
        
        # Recovery plan produces a working command
        mock_fm.plan_recovery.return_value = ModelPlan(
            thought="Fix error by running recovery command",
            command="echo 'recovery success'",
            explanation="Fixed command",
            raw_response="",
        )

        engine = GitAgentEngine(
            fm_client=mock_fm,
            max_retries=3,
            auto_confirm=True,
        )

        success = engine.execute_task("fix something")
        self.assertTrue(success)
        mock_fm.plan_action.assert_called_once()
        mock_fm.plan_recovery.assert_called_once()


if __name__ == "__main__":
    unittest.main()
