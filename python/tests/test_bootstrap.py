from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from agentappflow_bootstrap import BootstrapError, BootstrapRequest, bootstrap_project


class BootstrapProjectTests(unittest.TestCase):
    def create_repo(self) -> Path:
        temp_dir = Path(tempfile.mkdtemp(prefix="agentappflow-bootstrap-"))
        subprocess.run(
            ["git", "init"],
            cwd=temp_dir,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return temp_dir

    def make_request(self, repo_path: Path) -> BootstrapRequest:
        return BootstrapRequest(
            project_name="LegalPocketAI",
            project_description="iOS legal assistant for contract analysis.",
            project_path=str(repo_path),
            project_type="ios_app",
            platforms=["ios", "macos"],
            agent_tools=["codex", "claude_code"],
            approval_mode="propose",
            improvement_mode="propose",
        )

    def test_bootstrap_creates_framework_contract(self) -> None:
        repo_path = self.create_repo()
        result = bootstrap_project(self.make_request(repo_path))

        self.assertTrue(result.ok)
        self.assertTrue((repo_path / ".agentappflow" / "project.yaml").exists())
        self.assertTrue((repo_path / ".agentappflow" / "rules" / "core-rules.md").exists())
        self.assertTrue((repo_path / ".agentappflow" / "templates" / "task-template.md").exists())
        self.assertTrue((repo_path / "AGENTS.md").exists())
        self.assertTrue((repo_path / "CLAUDE.md").exists())
        project_yaml = (repo_path / ".agentappflow" / "project.yaml").read_text(encoding="utf-8")
        self.assertIn("project_description: |-", project_yaml)
        self.assertIn("iOS legal assistant for contract analysis.", project_yaml)
        self.assertIn(".agentappflow/project.yaml", result.created)
        self.assertIn("AGENTS.md", result.created)

    def test_second_bootstrap_run_is_non_destructive_without_force(self) -> None:
        repo_path = self.create_repo()
        request = self.make_request(repo_path)

        bootstrap_project(request)
        second_result = bootstrap_project(request)

        self.assertIn(".agentappflow/project.yaml", second_result.skipped)
        self.assertIn("AGENTS.md", second_result.skipped)
        self.assertEqual(second_result.created, [])

    def test_bootstrap_requires_git_repository(self) -> None:
        non_repo = Path(tempfile.mkdtemp(prefix="agentappflow-nonrepo-"))
        request = self.make_request(non_repo)

        with self.assertRaises(BootstrapError):
            bootstrap_project(request)

    def test_bootstrap_requires_existing_path(self) -> None:
        request = BootstrapRequest(
            project_name="MissingRepo",
            project_description="",
            project_path="/tmp/agentappflow-missing-repo",
            project_type="ios_app",
            platforms=["ios"],
            agent_tools=["codex"],
            approval_mode="propose",
            improvement_mode="propose",
        )

        with self.assertRaises(BootstrapError):
            bootstrap_project(request)


if __name__ == "__main__":
    unittest.main()
