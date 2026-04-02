from __future__ import annotations

import json
import os
import platform
import signal
import socket
import threading
import time
from pathlib import Path
from typing import Any

try:
    from .bootstrap import BootstrapError, BootstrapRequest, bootstrap_project, validate_bootstrap_exists
    from .storage import ProjectRegistry, SessionRegistry, default_data_directory
except ImportError:  # pragma: no cover - bundled resource import path
    from bootstrap import BootstrapError, BootstrapRequest, bootstrap_project, validate_bootstrap_exists
    from storage import ProjectRegistry, SessionRegistry, default_data_directory

RUNTIME_VERSION = "0.4.0"


class JSONRPCError(Exception):
    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class AgentAppFlowRuntime:
    def __init__(self, base_dir: Path | None = None) -> None:
        runtime_base = (base_dir or default_data_directory()).expanduser().resolve()
        self.base_dir = runtime_base
        self.project_registry = ProjectRegistry(runtime_base)
        self.session_registry = SessionRegistry(runtime_base)
        self.started_at_monotonic = time.monotonic()
        self.started_at_unix = time.time()
        self.socket_path: str | None = None

    def set_socket_path(self, socket_path: str | None) -> None:
        self.socket_path = socket_path

    def uptime_seconds(self) -> float:
        return round(time.monotonic() - self.started_at_monotonic, 3)

    def handle_request(self, payload: dict[str, Any]) -> dict[str, Any]:
        request_id = payload.get("id")
        method = payload.get("method")
        params = payload.get("params", {})
        if params is None:
            params = {}

        if not isinstance(method, str):
            return self._error_response(request_id, -32600, "Invalid JSON-RPC method.")
        if not isinstance(params, dict):
            return self._error_response(request_id, -32602, "JSON-RPC params must be an object.")

        try:
            handler = getattr(self, f"rpc_{method}")
        except AttributeError:
            return self._error_response(request_id, -32601, f"Unknown method: {method}")

        try:
            result = handler(params)
            return {"jsonrpc": "2.0", "id": request_id, "result": result}
        except BootstrapError as error:
            return self._error_response(request_id, -32000, str(error))
        except KeyError as error:
            return self._error_response(request_id, -32001, str(error))
        except JSONRPCError as error:
            return self._error_response(request_id, error.code, error.message)
        except Exception as error:  # pragma: no cover - defensive server handling
            return self._error_response(request_id, -32099, f"Unexpected runtime failure: {error}")

    def rpc_health_check(self, params: dict[str, Any]) -> dict[str, Any]:
        _ = params
        session_pipeline_ok = self.session_registry.base_dir.exists() and os.access(self.session_registry.base_dir, os.W_OK)
        proposals_path = self.project_registry.base_dir / "projects.json"
        improvement_queue_ok = proposals_path.parent.exists() and os.access(proposals_path.parent, os.R_OK)
        subsystems = [
            {
                "name": "process",
                "status": "ok",
                "detail": "Runtime process is alive and responding.",
            },
            {
                "name": "session_pipeline",
                "status": "ok" if session_pipeline_ok else "degraded",
                "detail": "Session storage is writable." if session_pipeline_ok else "Session storage is unavailable or not writable.",
            },
            {
                "name": "improvement_queue",
                "status": "ok" if improvement_queue_ok else "degraded",
                "detail": "Proposal and retro state is readable." if improvement_queue_ok else "Proposal or retro storage is unavailable.",
            },
        ]
        overall_status = "ok" if all(item["status"] == "ok" for item in subsystems) else "degraded"
        return {
            "status": overall_status,
            "version": RUNTIME_VERSION,
            "python_version": platform.python_version(),
            "uptime_seconds": self.uptime_seconds(),
            "registry_path": str(self.project_registry.registry_path),
            "project_count": len(self.project_registry.list_projects()),
            "socket_path": self.socket_path,
            "subsystems": subsystems,
        }

    def rpc_bootstrap_project(self, params: dict[str, Any]) -> dict[str, Any]:
        request = BootstrapRequest.from_dict(params)
        result = bootstrap_project(request, force=bool(params.get("force", False)))
        return result.to_dict()

    def rpc_register_project(self, params: dict[str, Any]) -> dict[str, Any]:
        request = BootstrapRequest.from_dict(params)
        request.validate()
        validate_bootstrap_exists(request.project_root)

        result_payload = params.get("bootstrap_result")
        if isinstance(result_payload, dict):
            command_result = self._decode_command_result(result_payload)
        else:
            command_result = bootstrap_project(request)
        project = self.project_registry.register_project(request, command_result)
        return project.to_dict()

    def rpc_list_projects(self, params: dict[str, Any]) -> list[dict[str, Any]]:
        _ = params
        return [item.to_dict() for item in self.project_registry.list_projects()]

    def rpc_get_project(self, params: dict[str, Any]) -> dict[str, Any]:
        project_id = str(params.get("id", "")).strip()
        if not project_id:
            raise JSONRPCError(-32602, "get_project requires id.")
        project = self.project_registry.get_project(project_id)
        if project is None:
            raise KeyError(f"Unknown project id: {project_id}")
        sessions = self.session_registry.list_sessions(project_id=project_id)
        latest_session = sessions[0] if sessions else None
        return {
            "project": project.to_dict(),
            "latest_session": latest_session.to_dict() if latest_session else None,
            "sessions": [item.to_dict() for item in sessions],
        }

    def rpc_start_session(self, params: dict[str, Any]) -> dict[str, Any]:
        project_id = str(params.get("project_id", "")).strip()
        if not project_id:
            raise JSONRPCError(-32602, "start_session requires project_id.")
        project = self.project_registry.get_project(project_id)
        if project is None:
            raise KeyError(f"Unknown project id: {project_id}")

        provided_title = str(params.get("title", "")).strip()
        title = provided_title or f"{project.project_name} Session"
        metadata = {
            "socket_path": self.socket_path,
            "runtime_version": RUNTIME_VERSION,
            "transport": "unix",
        }
        session = self.session_registry.start_session(project_id=project_id, title=title, metadata=metadata)
        self.project_registry.record_session_start(project_id, session)
        return {
            "session_id": session.id,
            "session": session.to_dict(),
            "runtime": metadata,
        }

    def rpc_record_task_result(self, params: dict[str, Any]) -> dict[str, Any]:
        session_id = str(params.get("session_id", "")).strip()
        if not session_id:
            raise JSONRPCError(-32602, "record_task_result requires session_id.")
        name = str(params.get("name", "")).strip()
        if not name:
            raise JSONRPCError(-32602, "record_task_result requires name.")
        status = str(params.get("status", "")).strip()
        if not status:
            raise JSONRPCError(-32602, "record_task_result requires status.")

        project_id = str(params.get("project_id", "")).strip() or None
        session = self.session_registry.record_task_result(
            session_id,
            name=name,
            status=status,
            outcome=str(params["outcome"]) if params.get("outcome") is not None else None,
            details=dict(params.get("details") or {}),
            task_id=str(params.get("task_id", "")).strip() or None,
            project_id=project_id,
        )
        self.project_registry.record_session_update(session.project_id, session)
        return {"session": session.to_dict()}

    def rpc_end_session(self, params: dict[str, Any]) -> dict[str, Any]:
        session_id = str(params.get("session_id", "")).strip()
        if not session_id:
            raise JSONRPCError(-32602, "end_session requires session_id.")
        project_id = str(params.get("project_id", "")).strip() or None
        outcome = str(params["outcome"]) if params.get("outcome") is not None else None
        status = str(params.get("status", "")).strip() or None

        session = self.session_registry.end_session(
            session_id,
            outcome=outcome,
            status=status,
            project_id=project_id,
        )
        self.project_registry.record_session_update(session.project_id, session)
        return {"session": session.to_dict()}

    def _decode_command_result(self, payload: dict[str, Any]):
        try:
            from .bootstrap import CommandResult
        except ImportError:  # pragma: no cover - bundled resource import path
            from bootstrap import CommandResult

        return CommandResult(
            ok=bool(payload.get("ok", True)),
            message=str(payload.get("message", "")),
            created=[str(item) for item in payload.get("created", [])],
            skipped=[str(item) for item in payload.get("skipped", [])],
            warnings=[str(item) for item in payload.get("warnings", [])],
        )

    def _error_response(self, request_id: Any, code: int, message: str) -> dict[str, Any]:
        return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


def _read_request(connection: socket.socket) -> dict[str, Any]:
    chunks: list[bytes] = []
    while True:
        data = connection.recv(65536)
        if not data:
            break
        chunks.append(data)
    if not chunks:
        raise JSONRPCError(-32700, "Empty JSON-RPC request.")
    return json.loads(b"".join(chunks).decode("utf-8"))


def _handle_connection(runtime: AgentAppFlowRuntime, connection: socket.socket) -> None:
    with connection:
        try:
            payload = _read_request(connection)
            response = runtime.handle_request(payload)
        except JSONRPCError as error:
            response = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": error.code, "message": error.message},
            }
        except Exception as error:  # pragma: no cover - top-level defensive path
            response = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": f"Invalid request: {error}"},
            }
        connection.sendall(json.dumps(response).encode("utf-8"))


def run_runtime_server(
    socket_path: str,
    *,
    base_dir: Path | None = None,
    verbose: bool = False,
) -> None:
    runtime = AgentAppFlowRuntime(base_dir=base_dir)
    socket_file = Path(socket_path).expanduser().resolve()
    socket_file.parent.mkdir(parents=True, exist_ok=True)
    runtime.set_socket_path(str(socket_file))

    if socket_file.exists():
        socket_file.unlink()

    shutdown_event = threading.Event()
    worker_threads: set[threading.Thread] = set()
    worker_lock = threading.Lock()

    def _shutdown_handler(signum: int, _frame: Any) -> None:
        if verbose:
            print(f"Received signal {signum}, shutting down AgentAppFlow runtime.", flush=True)
        shutdown_event.set()

    registered_handlers: dict[int, Any] = {}
    if threading.current_thread() is threading.main_thread():
        for signum in (signal.SIGINT, signal.SIGTERM):
            registered_handlers[signum] = signal.getsignal(signum)
            signal.signal(signum, _shutdown_handler)

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        try:
            server.bind(str(socket_file))
            os.chmod(socket_file, 0o600)
            server.listen(128)
            server.settimeout(0.25)

            if verbose:
                print(
                    f"AgentAppFlow runtime listening on {socket_file} (pid={os.getpid()})",
                    flush=True,
                )

            while not shutdown_event.is_set():
                try:
                    connection, _ = server.accept()
                except socket.timeout:
                    continue
                except OSError:
                    if shutdown_event.is_set():
                        break
                    raise

                thread = threading.Thread(
                    target=_handle_connection,
                    args=(runtime, connection),
                    daemon=True,
                )
                with worker_lock:
                    worker_threads.add(thread)
                thread.start()

                finished = {item for item in worker_threads if not item.is_alive()}
                if finished:
                    with worker_lock:
                        worker_threads.difference_update(finished)
        finally:
            shutdown_event.set()
            for thread in list(worker_threads):
                thread.join(timeout=1.0)
            try:
                if socket_file.exists():
                    socket_file.unlink()
            finally:
                if threading.current_thread() is threading.main_thread():
                    for signum, handler in registered_handlers.items():
                        signal.signal(signum, handler)
