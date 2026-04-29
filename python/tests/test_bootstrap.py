from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from agentappflow_bootstrap import BootstrapError, BootstrapRequest, bootstrap_project
from git_helpers import init_repo


class BootstrapProjectTests(unittest.TestCase):
    def create_repo(self) -> Path:
        temp_dir = Path(tempfile.mkdtemp(prefix="agentappflow-bootstrap-"))
        init_repo(temp_dir)
        return temp_dir

    def make_request(self, repo_path: Path, *, approval_mode: str = "propose") -> BootstrapRequest:
        return BootstrapRequest(
            project_name="LegalPocketAI",
            project_description="iOS legal assistant for contract analysis.",
            project_path=str(repo_path),
            project_type="ios_app",
            platforms=["ios", "macos"],
            agent_tools=["codex", "claude_code"],
            approval_mode=approval_mode,
            improvement_mode="propose",
        )

    def test_bootstrap_creates_phase_four_framework_contract(self) -> None:
        repo_path = self.create_repo()
        result = bootstrap_project(self.make_request(repo_path))

        self.assertTrue(result.ok)
        self.assertTrue((repo_path / ".agentappflow" / "project.yaml").exists())
        self.assertTrue((repo_path / ".agentappflow" / "rules" / "default.md").exists())
        self.assertTrue((repo_path / ".agentappflow" / "templates" / "session.md").exists())
        self.assertTrue((repo_path / ".agentappflow" / "templates" / "retro.md").exists())
        self.assertTrue((repo_path / "AGENTS.md").exists())
        self.assertTrue((repo_path / "CLAUDE.md").exists())

        project_yaml = (repo_path / ".agentappflow" / "project.yaml").read_text(encoding="utf-8")
        self.assertIn("project_description: |-",
                      project_yaml)
        self.assertIn("iOS legal assistant for contract analysis.", project_yaml)
        self.assertIn("approval_mode: propose", project_yaml)
        self.assertIn(".agentappflow/project.yaml", result.created)
        self.assertIn("AGENTS.md", result.created)

    def test_second_bootstrap_run_is_idempotent_without_duplicate_writes(self) -> None:
        repo_path = self.create_repo()
        request = self.make_request(repo_path)

        bootstrap_project(request)
        second_result = bootstrap_project(request)

        self.assertIn(".agentappflow/project.yaml", second_result.skipped)
        self.assertIn("AGENTS.md", second_result.skipped)
        self.assertEqual(second_result.created, [])

    def test_re_running_bootstrap_preserves_divergent_files_without_force(self) -> None:
        repo_path = self.create_repo()
        bootstrap_project(self.make_request(repo_path))
        agents_path = repo_path / "AGENTS.md"
        agents_path.write_text("# Existing repo instructions\n", encoding="utf-8")

        updated_request = BootstrapRequest(
            project_name="LegalPocketAI",
            project_description="Updated framework description for the repository.",
            project_path=str(repo_path),
            project_type="ios_app",
            platforms=["ios"],
            agent_tools=["codex"],
            approval_mode="propose",
            improvement_mode="observe",
        )
        result = bootstrap_project(updated_request)

        project_yaml = (repo_path / ".agentappflow" / "project.yaml").read_text(encoding="utf-8")
        self.assertIn("iOS legal assistant for contract analysis.", project_yaml)
        self.assertNotIn("Updated framework description for the repository.", project_yaml)
        self.assertEqual(agents_path.read_text(encoding="utf-8"), "# Existing repo instructions\n")
        self.assertIn(".agentappflow/project.yaml", result.skipped)
        self.assertIn("AGENTS.md", result.skipped)
        self.assertEqual(result.created, [])
        self.assertTrue(any(".agentappflow/project.yaml" in warning for warning in result.warnings))
        self.assertTrue(any("AGENTS.md" in warning for warning in result.warnings))

    def test_force_bootstrap_updates_changed_contract_fields(self) -> None:
        repo_path = self.create_repo()
        bootstrap_project(self.make_request(repo_path))
        (repo_path / "AGENTS.md").write_text("# Existing repo instructions\n", encoding="utf-8")

        updated_request = BootstrapRequest(
            project_name="LegalPocketAI",
            project_description="Updated framework description for the repository.",
            project_path=str(repo_path),
            project_type="ios_app",
            platforms=["ios"],
            agent_tools=["codex"],
            approval_mode="propose",
            improvement_mode="observe",
        )
        result = bootstrap_project(updated_request, force=True)

        project_yaml = (repo_path / ".agentappflow" / "project.yaml").read_text(encoding="utf-8")
        self.assertIn("Updated framework description for the repository.", project_yaml)
        self.assertIn("improvement_mode: observe", project_yaml)
        self.assertIn(".agentappflow/project.yaml", result.created)
        self.assertIn("AGENTS.md", result.created)
        self.assertNotIn(".agentappflow/project.yaml", result.skipped)

    def test_manual_approval_mode_is_normalized_with_warning(self) -> None:
        repo_path = self.create_repo()
        result = bootstrap_project(self.make_request(repo_path, approval_mode="manual"))

        project_yaml = (repo_path / ".agentappflow" / "project.yaml").read_text(encoding="utf-8")
        self.assertIn("approval_mode: observe", project_yaml)
        self.assertEqual(len(result.warnings), 1)

    def test_bootstrap_requires_git_repository(self) -> None:
        non_repo = Path(tempfile.mkdtemp(prefix="agentappflow-nonrepo-"))
        request = self.make_request(non_repo)

        with self.assertRaises(BootstrapError):
            bootstrap_project(request)

    def test_bootstrap_requires_repo_root_not_nested_git_subdirectory(self) -> None:
        repo_path = self.create_repo()
        nested_path = repo_path / "nested"
        nested_path.mkdir()
        request = self.make_request(nested_path)

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
