from __future__ import annotations

import io
import json
import os
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import agentappflow_bootstrap as cli_module
from git_helpers import init_repo


class CLISmokeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[2]
        self.runtime_home = Path(tempfile.mkdtemp(prefix="agentappflow-cli-runtime-"))
        self.project_repo = Path(tempfile.mkdtemp(prefix="agentappflow-cli-project-"))
        init_repo(self.project_repo)
        self.request_path = self.project_repo / "bootstrap-request.json"
        self.request_path.write_text(
            json.dumps(
                {
                    "project_name": "CLI Repo",
                    "project_description": "CLI smoke flow repository.",
                    "project_path": str(self.project_repo),
                    "project_type": "ios_app",
                    "platforms": ["ios", "macos"],
                    "agent_tools": ["codex", "claude_code"],
                    "approval_mode": "propose",
                    "improvement_mode": "observe",
                }
            ),
            encoding="utf-8",
        )

    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "python/agentappflow_bootstrap.py", *args],
            cwd=self.repo_root,
            env={**os.environ, "AGENTAPPFLOW_RUNTIME_HOME": str(self.runtime_home)},
            check=False,
            capture_output=True,
            text=True,
        )

    def run_main(self, args: list[str], *, stdin: str = "") -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch.dict("os.environ", {"AGENTAPPFLOW_RUNTIME_HOME": str(self.runtime_home)}, clear=False):
            with mock.patch("sys.stdin", io.StringIO(stdin)):
                with redirect_stdout(stdout), redirect_stderr(stderr):
                    exit_code = cli_module.main(args)
        return exit_code, stdout.getvalue(), stderr.getvalue()

    def test_full_cli_smoke_flow(self) -> None:
        bootstrap = self.run_cli("bootstrap", "--input", str(self.request_path))
        self.assertEqual(bootstrap.returncode, 0, bootstrap.stdout + bootstrap.stderr)
        bootstrap_payload = json.loads(bootstrap.stdout)
        self.assertTrue(bootstrap_payload["ok"])

        register = self.run_cli("register", "--input", str(self.request_path))
        self.assertEqual(register.returncode, 0, register.stdout + register.stderr)
        register_payload = json.loads(register.stdout)
        project_id = register_payload["project"]["id"]

        listed = self.run_cli("list", "--format", "json")
        self.assertEqual(listed.returncode, 0, listed.stdout + listed.stderr)
        listed_payload = json.loads(listed.stdout)
        self.assertEqual(len(listed_payload), 1)

        status = self.run_cli("status", "--format", "json")
        self.assertEqual(status.returncode, 0, status.stdout + status.stderr)
        status_payload = json.loads(status.stdout)
        self.assertEqual(status_payload["project_count"], 1)

        started = self.run_cli("session", "start", project_id, "--title", "CLI session")
        self.assertEqual(started.returncode, 0, started.stdout + started.stderr)
        started_payload = json.loads(started.stdout)
        self.assertEqual(started_payload["session"]["title"], "CLI session")

        sessions = self.run_cli("session", "list", project_id, "--format", "json")
        self.assertEqual(sessions.returncode, 0, sessions.stdout + sessions.stderr)
        sessions_payload = json.loads(sessions.stdout)
        self.assertEqual(len(sessions_payload), 1)

    def test_in_process_main_covers_table_output_and_stdin_input(self) -> None:
        request_payload = self.request_path.read_text(encoding="utf-8")

        exit_code, stdout, _stderr = self.run_main(["bootstrap", "--stdin"], stdin=request_payload)
        self.assertEqual(exit_code, 0)
        self.assertTrue(json.loads(stdout)["ok"])

        exit_code, stdout, stderr = self.run_main(["--verbose", "register", "--input", str(self.request_path)])
        self.assertEqual(exit_code, 0)
        project_id = json.loads(stdout)["project"]["id"]
        self.assertIn("Registering project", stderr)

        exit_code, stdout, _stderr = self.run_main(["list", "--format", "table"])
        self.assertEqual(exit_code, 0)
        self.assertIn("CLI Repo", stdout)

        exit_code, stdout, _stderr = self.run_main(["status", "--format", "table"])
        self.assertEqual(exit_code, 0)
        self.assertIn("Project count:", stdout)

        exit_code, stdout, _stderr = self.run_main(["session", "start", project_id, "--title", "In-process"])
        self.assertEqual(exit_code, 0)
        self.assertEqual(json.loads(stdout)["session"]["title"], "In-process")

        exit_code, stdout, _stderr = self.run_main(["session", "list", project_id, "--format", "table"])
        self.assertEqual(exit_code, 0)
        self.assertIn("In-process", stdout)

    def test_cli_validation_and_runtime_error_exit_codes(self) -> None:
        exit_code, stdout, _stderr = self.run_main(["bootstrap", "--stdin"], stdin="")
        self.assertEqual(exit_code, 1)
        self.assertFalse(json.loads(stdout)["ok"])

        with mock.patch.object(cli_module, "run_runtime_server", side_effect=OSError("socket failure")):
            exit_code, stdout, stderr = self.run_main(["--verbose", "serve", "--socket", "/tmp/agentappflow-test.sock"])
        self.assertEqual(exit_code, 2)
        self.assertEqual(json.loads(stdout)["category"], "runtime_error")
        self.assertIn("Starting runtime server", stderr)


if __name__ == "__main__":
    unittest.main()
