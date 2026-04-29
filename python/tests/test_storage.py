from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "agentappflow_core"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from bootstrap import BootstrapRequest, CommandResult
from git_helpers import init_repo
from storage import ProjectRegistry, SessionRegistry, atomic_write_text


class StorageTests(unittest.TestCase):
    def create_repo(self) -> Path:
        temp_dir = Path(tempfile.mkdtemp(prefix="agentappflow-storage-repo-"))
        init_repo(temp_dir)
        return temp_dir

    def make_request(self, repo_path: Path) -> BootstrapRequest:
        return BootstrapRequest(
            project_name="StorageRepo",
            project_description="Storage validation repo.",
            project_path=str(repo_path),
            project_type="ios_app",
            platforms=["ios"],
            agent_tools=["codex"],
            approval_mode="propose",
            improvement_mode="observe",
        )

    def make_result(self) -> CommandResult:
        return CommandResult(
            ok=True,
            message="ok",
            created=[".agentappflow/project.yaml"],
            skipped=[],
            warnings=[],
        )

    def test_project_registry_migrates_v1_list_payload_to_versioned_payload(self) -> None:
        base_dir = Path(tempfile.mkdtemp(prefix="agentappflow-project-registry-"))
        registry_path = base_dir / "runtime" / "projects.json"
        registry_path.parent.mkdir(parents=True, exist_ok=True)
        registry_path.write_text(
            json.dumps(
                [
                    {
                        "id": "project-1",
                        "project_name": "Legacy Project",
                        "project_description": "",
                        "project_path": "/tmp/legacy-project",
                        "project_type": "ios_app",
                        "platforms": ["ios"],
                        "agent_tools": ["codex"],
                        "approval_mode": "propose",
                        "improvement_mode": "observe",
                        "created_items": [],
                        "skipped_items": [],
                        "registered_at": "2026-01-01T00:00:00+00:00",
                        "updated_at": "2026-01-01T00:00:00+00:00",
                        "last_bootstrapped_at": "2026-01-01T00:00:00+00:00",
                        "session_count": 0,
                    }
                ]
            ),
            encoding="utf-8",
        )

        registry = ProjectRegistry(base_dir)
        projects = registry.list_projects()
        self.assertEqual(len(projects), 1)

        migrated_payload = json.loads(registry_path.read_text(encoding="utf-8"))
        self.assertEqual(migrated_payload["version"], 2)
        self.assertEqual(len(migrated_payload["projects"]), 1)

    def test_atomic_write_preserves_existing_file_when_replace_fails(self) -> None:
        base_dir = Path(tempfile.mkdtemp(prefix="agentappflow-atomic-write-"))
        file_path = base_dir / "runtime" / "projects.json"
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text('{"version": 1}', encoding="utf-8")

        with mock.patch("storage.os.replace", side_effect=RuntimeError("replace failed")):
            with self.assertRaises(RuntimeError):
                atomic_write_text(file_path, '{"version": 2}')

        self.assertEqual(file_path.read_text(encoding="utf-8"), '{"version": 1}')

    def test_session_registry_migrates_legacy_sessions_and_appends_updates(self) -> None:
        base_dir = Path(tempfile.mkdtemp(prefix="agentappflow-session-registry-"))
        runtime_dir = base_dir / "runtime"
        runtime_dir.mkdir(parents=True, exist_ok=True)
        legacy_path = runtime_dir / "sessions.json"
        legacy_path.write_text(
            json.dumps(
                [
                    {
                        "id": "legacy-session",
                        "project_id": "project-1",
                        "title": "Legacy",
                        "status": "running",
                        "created_at": "2026-01-01T00:00:00+00:00",
                        "started_at": "2026-01-01T00:00:00+00:00",
                    }
                ]
            ),
            encoding="utf-8",
        )

        sessions = SessionRegistry(base_dir)
        migrated = sessions.list_sessions(project_id="project-1")
        self.assertEqual(len(migrated), 1)
        self.assertFalse(legacy_path.exists())

        updated = sessions.record_task_result(
            "legacy-session",
            project_id="project-1",
            name="Migrate session",
            status="completed",
            outcome="success",
            details={"source": "legacy"},
        )
        finished = sessions.end_session("legacy-session", project_id="project-1", outcome="success")
        self.assertEqual(len(updated.task_results), 1)
        self.assertEqual(finished.status, "completed")

        session_file = runtime_dir / "sessions" / "project-1.ndjson"
        self.assertTrue(session_file.exists())
        self.assertEqual(len(session_file.read_text(encoding="utf-8").strip().splitlines()), 3)

    def test_session_registry_migrates_legacy_sessions_even_when_ndjson_exists(self) -> None:
        base_dir = Path(tempfile.mkdtemp(prefix="agentappflow-session-mixed-"))
        runtime_dir = base_dir / "runtime"
        sessions_dir = runtime_dir / "sessions"
        sessions_dir.mkdir(parents=True, exist_ok=True)
        (sessions_dir / "existing.ndjson").write_text("", encoding="utf-8")
        legacy_path = runtime_dir / "sessions.json"
        legacy_path.write_text(
            json.dumps(
                [
                    {
                        "id": "legacy-session",
                        "project_id": "project-1",
                        "title": "Legacy",
                        "status": "running",
                        "created_at": "2026-01-01T00:00:00+00:00",
                        "started_at": "2026-01-01T00:00:00+00:00",
                    }
                ]
            ),
            encoding="utf-8",
        )

        sessions = SessionRegistry(base_dir)

        self.assertFalse(legacy_path.exists())
        migrated = sessions.list_sessions(project_id="project-1")
        self.assertEqual(len(migrated), 1)
        self.assertTrue((sessions_dir / "project-1.ndjson").exists())

    def test_session_registry_rejects_project_id_path_traversal(self) -> None:
        base_dir = Path(tempfile.mkdtemp(prefix="agentappflow-session-traversal-"))
        sessions = SessionRegistry(base_dir)
        outside_path = base_dir / "runtime" / "outside.ndjson"

        with self.assertRaises(ValueError):
            sessions.start_session(project_id="../outside", title="Invalid")
        with self.assertRaises(ValueError):
            sessions.list_sessions(project_id="../outside")

        self.assertFalse(outside_path.exists())
        self.assertFalse((base_dir / "outside.ndjson").exists())

    def test_session_registry_rejects_session_id_path_traversal(self) -> None:
        base_dir = Path(tempfile.mkdtemp(prefix="agentappflow-session-id-traversal-"))
        sessions = SessionRegistry(base_dir)
        session = sessions.start_session(project_id="project-1", title="Valid")

        with self.assertRaises(ValueError):
            sessions.record_task_result(
                "../outside",
                project_id="project-1",
                name="Invalid",
                status="completed",
                outcome="success",
            )
        with self.assertRaises(ValueError):
            sessions.end_session("../outside", project_id="project-1", outcome="success")

        self.assertEqual(sessions.get_session(session.id, project_id="project-1").id, session.id)
        self.assertFalse((base_dir / "runtime" / "outside.ndjson").exists())

    def test_find_by_path_returns_registered_project(self) -> None:
        repo_path = self.create_repo()
        base_dir = Path(tempfile.mkdtemp(prefix="agentappflow-project-find-"))
        registry = ProjectRegistry(base_dir)
        request = self.make_request(repo_path)
        project = registry.register_project(request, self.make_result())

        found = registry.find_by_path(str(repo_path))
        self.assertIsNotNone(found)
        self.assertEqual(found.id, project.id)


if __name__ == "__main__":
    unittest.main()
