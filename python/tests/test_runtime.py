from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "agentappflow_core"))

from bootstrap import BootstrapRequest, bootstrap_project
from runtime import AgentAppFlowRuntime
from storage import default_data_directory


class RuntimeWorkflowTests(unittest.TestCase):
    def create_repo(self) -> Path:
        temp_dir = Path(tempfile.mkdtemp(prefix="agentappflow-runtime-"))
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
            project_name="RuntimeRepo",
            project_description="Local runtime bootstrap validation repo.",
            project_path=str(repo_path),
            project_type="ios_app",
            platforms=["ios", "macos"],
            agent_tools=["codex", "claude_code"],
            approval_mode="propose",
            improvement_mode="propose",
        )

    def test_register_project_and_start_session(self) -> None:
        repo_path = self.create_repo()
        request = self.make_request(repo_path)
        bootstrap_result = bootstrap_project(request)
        runtime = AgentAppFlowRuntime(base_dir=Path(tempfile.mkdtemp(prefix="agentappflow-data-")))

        register_response = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "1",
                "method": "register_project",
                "params": {
                    "project_name": request.project_name,
                    "project_description": request.project_description,
                    "project_path": request.project_path,
                    "project_type": request.project_type,
                    "platforms": request.platforms,
                    "agent_tools": request.agent_tools,
                    "approval_mode": request.approval_mode,
                    "improvement_mode": request.improvement_mode,
                    "bootstrap_result": bootstrap_result.to_dict(),
                },
            }
        )

        project = register_response["result"]["project"]
        self.assertEqual(project["project_name"], "RuntimeRepo")
        self.assertEqual(project["session_count"], 0)

        list_response = runtime.handle_request(
            {"jsonrpc": "2.0", "id": "2", "method": "list_projects", "params": {}}
        )
        self.assertEqual(len(list_response["result"]["projects"]), 1)

        session_response = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "3",
                "method": "start_session",
                "params": {"project_id": project["id"], "title": "Investigate runtime health"},
            }
        )
        session = session_response["result"]["session"]
        self.assertEqual(session["title"], "Investigate runtime health")

        detail_response = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "4",
                "method": "get_project",
                "params": {"id": project["id"]},
            }
        )
        self.assertEqual(detail_response["result"]["latest_session"]["id"], session["id"])
        self.assertEqual(detail_response["result"]["project"]["session_count"], 1)

    def test_register_project_updates_existing_record_for_same_path(self) -> None:
        repo_path = self.create_repo()
        runtime = AgentAppFlowRuntime(base_dir=Path(tempfile.mkdtemp(prefix="agentappflow-data-")))

        first_request = self.make_request(repo_path)
        first_result = bootstrap_project(first_request)
        first_project = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "1",
                "method": "register_project",
                "params": {
                    "project_name": first_request.project_name,
                    "project_description": first_request.project_description,
                    "project_path": first_request.project_path,
                    "project_type": first_request.project_type,
                    "platforms": first_request.platforms,
                    "agent_tools": first_request.agent_tools,
                    "approval_mode": first_request.approval_mode,
                    "improvement_mode": first_request.improvement_mode,
                    "bootstrap_result": first_result.to_dict(),
                },
            }
        )["result"]["project"]

        second_request = BootstrapRequest(
            project_name="RuntimeRepo Renamed",
            project_description="Updated repo summary.",
            project_path=str(repo_path),
            project_type="ios_app",
            platforms=["ios"],
            agent_tools=["codex"],
            approval_mode="manual",
            improvement_mode="observe",
        )
        second_result = bootstrap_project(second_request)
        second_project = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "2",
                "method": "register_project",
                "params": {
                    "project_name": second_request.project_name,
                    "project_description": second_request.project_description,
                    "project_path": second_request.project_path,
                    "project_type": second_request.project_type,
                    "platforms": second_request.platforms,
                    "agent_tools": second_request.agent_tools,
                    "approval_mode": second_request.approval_mode,
                    "improvement_mode": second_request.improvement_mode,
                    "bootstrap_result": second_result.to_dict(),
                },
            }
        )["result"]["project"]

        self.assertEqual(first_project["id"], second_project["id"])
        self.assertEqual(second_project["project_name"], "RuntimeRepo Renamed")
        self.assertEqual(second_project["approval_mode"], "manual")

    def test_runtime_home_override_is_used_for_storage(self) -> None:
        runtime_home = Path(tempfile.mkdtemp(prefix="agentappflow-runtime-home-")).resolve()

        with mock.patch.dict("os.environ", {"AGENTAPPFLOW_RUNTIME_HOME": str(runtime_home)}, clear=False):
            self.assertEqual(default_data_directory(), runtime_home)
            runtime = AgentAppFlowRuntime()
            self.assertEqual(runtime.project_registry.base_dir, runtime_home)
            self.assertEqual(runtime.session_registry.base_dir, runtime_home)


if __name__ == "__main__":
    unittest.main()
