from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "agentappflow_core"))

import runtime as runtime_module
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

    def start_live_runtime(self, runtime_home: Path, socket_path: Path) -> subprocess.Popen[str]:
        process = subprocess.Popen(
            [
                sys.executable,
                "python/agentappflow_bootstrap.py",
                "--verbose",
                "serve",
                "--socket",
                str(socket_path),
            ],
            cwd=Path(__file__).resolve().parents[2],
            env={**os.environ, "AGENTAPPFLOW_RUNTIME_HOME": str(runtime_home)},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        deadline = time.time() + 5
        while time.time() < deadline:
            if socket_path.exists():
                return process
            time.sleep(0.05)
        output = process.stdout.read() if process.stdout is not None else ""
        process.terminate()
        raise AssertionError(f"Runtime socket was not created. Output:\n{output}")

    def send_jsonrpc(self, socket_path: Path, payload: dict[str, object]) -> dict[str, object]:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.connect(str(socket_path))
            client.sendall(json.dumps(payload).encode("utf-8"))
            client.shutdown(socket.SHUT_WR)
            chunks: list[bytes] = []
            while True:
                data = client.recv(65536)
                if not data:
                    break
                chunks.append(data)
        return json.loads(b"".join(chunks).decode("utf-8"))

    def test_register_project_start_session_record_task_and_end_session(self) -> None:
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
                    **request.to_dict(),
                    "bootstrap_result": bootstrap_result.to_dict(),
                },
            }
        )

        project = register_response["result"]
        self.assertEqual(project["project_name"], "RuntimeRepo")
        self.assertEqual(project["session_count"], 0)

        list_response = runtime.handle_request(
            {"jsonrpc": "2.0", "id": "2", "method": "list_projects", "params": {}}
        )
        self.assertEqual(len(list_response["result"]), 1)

        session_response = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "3",
                "method": "start_session",
                "params": {"project_id": project["id"], "title": "Investigate runtime health"},
            }
        )
        session = session_response["result"]["session"]
        self.assertEqual(session_response["result"]["session_id"], session["id"])
        self.assertEqual(session["title"], "Investigate runtime health")

        record_response = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "4",
                "method": "record_task_result",
                "params": {
                    "project_id": project["id"],
                    "session_id": session["id"],
                    "name": "Run smoke validation",
                    "status": "completed",
                    "outcome": "success",
                    "details": {"command": "python3 -m pytest python/tests"},
                },
            }
        )
        self.assertEqual(len(record_response["result"]["session"]["task_results"]), 1)

        end_response = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "5",
                "method": "end_session",
                "params": {
                    "project_id": project["id"],
                    "session_id": session["id"],
                    "outcome": "success",
                },
            }
        )
        self.assertEqual(end_response["result"]["session"]["status"], "completed")

        detail_response = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "6",
                "method": "get_project",
                "params": {"id": project["id"]},
            }
        )
        self.assertEqual(detail_response["result"]["latest_session"]["id"], session["id"])
        self.assertEqual(detail_response["result"]["project"]["session_count"], 1)
        self.assertEqual(len(detail_response["result"]["sessions"]), 1)

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
                    **first_request.to_dict(),
                    "bootstrap_result": first_result.to_dict(),
                },
            }
        )["result"]

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
                    **second_request.to_dict(),
                    "bootstrap_result": second_result.to_dict(),
                },
            }
        )["result"]

        self.assertEqual(first_project["id"], second_project["id"])
        self.assertEqual(second_project["project_name"], "RuntimeRepo Renamed")
        self.assertEqual(second_project["approval_mode"], "observe")

    def test_concurrent_session_starts_preserve_session_count(self) -> None:
        repo_path = self.create_repo()
        request = self.make_request(repo_path)
        bootstrap_result = bootstrap_project(request)
        runtime = AgentAppFlowRuntime(base_dir=Path(tempfile.mkdtemp(prefix="agentappflow-concurrent-")))
        project = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "1",
                "method": "register_project",
                "params": {
                    **request.to_dict(),
                    "bootstrap_result": bootstrap_result.to_dict(),
                },
            }
        )["result"]

        errors: list[BaseException] = []

        def worker(index: int) -> None:
            try:
                runtime.rpc_start_session({"project_id": project["id"], "title": f"Parallel {index}"})
            except BaseException as error:  # pragma: no cover - test diagnostic path
                errors.append(error)

        threads = [threading.Thread(target=worker, args=(index,)) for index in range(20)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(errors, [])
        updated_project = runtime.project_registry.get_project(project["id"])
        sessions = runtime.session_registry.list_sessions(project["id"])
        self.assertIsNotNone(updated_project)
        self.assertEqual(updated_project.session_count, 20)
        self.assertEqual(len(sessions), 20)

    def test_runtime_home_override_is_used_for_storage(self) -> None:
        runtime_home = Path(tempfile.mkdtemp(prefix="agentappflow-runtime-home-")).resolve()

        with mock.patch.dict("os.environ", {"AGENTAPPFLOW_RUNTIME_HOME": str(runtime_home)}, clear=False):
            self.assertEqual(default_data_directory(), runtime_home)
            runtime = AgentAppFlowRuntime()
            self.assertEqual(runtime.project_registry.base_dir, runtime_home)
            self.assertEqual(runtime.session_registry.base_dir, runtime_home)

    def test_handle_request_returns_jsonrpc_errors_for_invalid_payloads(self) -> None:
        runtime = AgentAppFlowRuntime(base_dir=Path(tempfile.mkdtemp(prefix="agentappflow-invalid-")))

        invalid_method = runtime.handle_request({"jsonrpc": "2.0", "id": "1", "method": None, "params": {}})
        self.assertEqual(invalid_method["error"]["code"], -32600)

        invalid_params = runtime.handle_request(
            {"jsonrpc": "2.0", "id": "2", "method": "health_check", "params": []}
        )
        self.assertEqual(invalid_params["error"]["code"], -32602)

        unknown_method = runtime.handle_request(
            {"jsonrpc": "2.0", "id": "3", "method": "unknown_method", "params": {}}
        )
        self.assertEqual(unknown_method["error"]["code"], -32601)

    def test_rpc_validation_errors_are_reported(self) -> None:
        runtime = AgentAppFlowRuntime(base_dir=Path(tempfile.mkdtemp(prefix="agentappflow-rpc-errors-")))

        get_project_error = runtime.handle_request(
            {"jsonrpc": "2.0", "id": "1", "method": "get_project", "params": {}}
        )
        self.assertEqual(get_project_error["error"]["code"], -32602)

        start_session_error = runtime.handle_request(
            {"jsonrpc": "2.0", "id": "2", "method": "start_session", "params": {}}
        )
        self.assertEqual(start_session_error["error"]["code"], -32602)

        record_task_error = runtime.handle_request(
            {
                "jsonrpc": "2.0",
                "id": "3",
                "method": "record_task_result",
                "params": {"session_id": "", "name": "", "status": ""},
            }
        )
        self.assertEqual(record_task_error["error"]["code"], -32602)

        end_session_error = runtime.handle_request(
            {"jsonrpc": "2.0", "id": "4", "method": "end_session", "params": {}}
        )
        self.assertEqual(end_session_error["error"]["code"], -32602)

    def test_in_process_server_loop_handles_one_request_and_cleans_up(self) -> None:
        runtime_home = Path(tempfile.mkdtemp(prefix="agentappflow-runtime-loop-"))
        socket_path = Path("/tmp") / f"agentappflow-loop-{os.getpid()}-{int(time.time() * 1000)}.sock"

        class FakeEvent:
            def __init__(self) -> None:
                self.flag = False

            def set(self) -> None:
                self.flag = True

            def is_set(self) -> bool:
                return self.flag

        class FakeConnection:
            def __init__(self) -> None:
                self._chunks = [
                    json.dumps(
                        {"jsonrpc": "2.0", "id": "health", "method": "health_check", "params": {}}
                    ).encode("utf-8"),
                    b"",
                ]
                self.sent = b""

            def recv(self, _size: int) -> bytes:
                return self._chunks.pop(0)

            def sendall(self, data: bytes) -> None:
                self.sent += data

            def __enter__(self) -> "FakeConnection":
                return self

            def __exit__(self, _exc_type, _exc, _tb) -> None:
                return None

        fake_event = FakeEvent()
        fake_connection = FakeConnection()

        class FakeThread:
            def __init__(self, *, target, args, daemon) -> None:
                self.target = target
                self.args = args
                self.daemon = daemon
                self._alive = False

            def start(self) -> None:
                self._alive = True
                self.target(*self.args)
                self._alive = False
                fake_event.set()

            def is_alive(self) -> bool:
                return self._alive

            def join(self, timeout: float | None = None) -> None:
                _ = timeout

        class FakeServer:
            def __init__(self, *_args, **_kwargs) -> None:
                self.accepted = False

            def __enter__(self) -> "FakeServer":
                return self

            def __exit__(self, _exc_type, _exc, _tb) -> None:
                return None

            def bind(self, _path: str) -> None:
                return None

            def listen(self, _backlog: int) -> None:
                return None

            def settimeout(self, _timeout: float) -> None:
                return None

            def accept(self):
                if not self.accepted:
                    self.accepted = True
                    return fake_connection, None
                raise socket.timeout()

        with mock.patch.object(runtime_module.threading, "Event", return_value=fake_event), mock.patch.object(
            runtime_module.threading,
            "Thread",
            side_effect=lambda *args, **kwargs: FakeThread(**kwargs),
        ), mock.patch.object(
            runtime_module.threading, "current_thread", return_value=runtime_module.threading.main_thread()
        ), mock.patch.object(
            runtime_module.socket, "socket", side_effect=lambda *args, **kwargs: FakeServer()
        ), mock.patch.object(
            runtime_module.signal, "getsignal", return_value=signal.SIG_DFL
        ), mock.patch.object(
            runtime_module.signal, "signal", side_effect=lambda *args, **kwargs: None
        ), mock.patch.object(
            runtime_module.os, "chmod", side_effect=lambda *args, **kwargs: None
        ):
            runtime_module.run_runtime_server(str(socket_path), base_dir=runtime_home, verbose=True)

        response_payload = json.loads(fake_connection.sent.decode("utf-8"))
        self.assertEqual(response_payload["result"]["status"], "ok")

    def test_live_socket_server_handles_health_check_and_concurrency(self) -> None:
        repo_path = self.create_repo()
        request = self.make_request(repo_path)
        bootstrap_project(request)
        runtime_home = Path(tempfile.mkdtemp(prefix="agentappflow-runtime-home-"))
        socket_path = Path("/tmp") / f"agentappflow-{os.getpid()}-{int(time.time() * 1000)}.sock"

        project_runtime = AgentAppFlowRuntime(base_dir=runtime_home)
        project_runtime.rpc_register_project({**request.to_dict()})

        process = self.start_live_runtime(runtime_home, socket_path)
        try:
            health = self.send_jsonrpc(
                socket_path,
                {"jsonrpc": "2.0", "id": "health", "method": "health_check", "params": {}},
            )
            self.assertEqual(health["result"]["status"], "ok")
            self.assertEqual(health["result"]["project_count"], 1)
            self.assertEqual(len(health["result"]["subsystems"]), 3)
            subsystem_names = {item["name"] for item in health["result"]["subsystems"]}
            self.assertEqual(subsystem_names, {"process", "session_pipeline", "improvement_queue"})

            responses: list[dict[str, object]] = []
            errors: list[BaseException] = []

            def worker(index: int) -> None:
                try:
                    response = self.send_jsonrpc(
                        socket_path,
                        {
                            "jsonrpc": "2.0",
                            "id": str(index),
                            "method": "health_check",
                            "params": {},
                        },
                    )
                    responses.append(response)
                except BaseException as error:  # pragma: no cover - test diagnostic path
                    errors.append(error)

            threads = [threading.Thread(target=worker, args=(index,)) for index in range(50)]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()

            self.assertEqual(errors, [])
            self.assertEqual(len(responses), 50)
            self.assertTrue(all(response["result"]["status"] == "ok" for response in responses))
        finally:
            process.terminate()
            process.wait(timeout=5)
            if socket_path.exists():
                socket_path.unlink()


if __name__ == "__main__":
    unittest.main()
