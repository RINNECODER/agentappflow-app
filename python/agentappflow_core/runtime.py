from __future__ import annotations

import json
import os
import socket
from pathlib import Path
from typing import Any

try:
    from .bootstrap import BootstrapError, BootstrapRequest, bootstrap_project
    from .storage import ProjectRegistry, SessionRegistry, default_data_directory
except ImportError:  # pragma: no cover - bundled resource import path
    from bootstrap import BootstrapError, BootstrapRequest, bootstrap_project
    from storage import ProjectRegistry, SessionRegistry, default_data_directory

RUNTIME_VERSION = "0.2.0"


class JSONRPCError(Exception):
    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class AgentAppFlowRuntime:
    def __init__(self, base_dir: Path | None = None) -> None:
        runtime_base = (base_dir or default_data_directory()).expanduser().resolve()
        self.project_registry = ProjectRegistry(runtime_base)
        self.session_registry = SessionRegistry(runtime_base)

    def handle_request(self, payload: dict[str, Any]) -> dict[str, Any]:
        request_id = payload.get("id")
        method = payload.get("method")
        params = payload.get("params") or {}

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
        return {"status": "ok", "version": RUNTIME_VERSION}

    def rpc_bootstrap_project(self, params: dict[str, Any]) -> dict[str, Any]:
        request = BootstrapRequest.from_dict(params)
        result = bootstrap_project(request, force=bool(params.get("force", False)))
        return result.to_dict()

    def rpc_register_project(self, params: dict[str, Any]) -> dict[str, Any]:
        request = BootstrapRequest.from_dict(params)
        result_payload = params.get("bootstrap_result")
        if not isinstance(result_payload, dict):
            raise JSONRPCError(-32602, "register_project requires bootstrap_result.")
        result = self.rpc_bootstrap_project(params) if result_payload.get("ok") is None else result_payload
        command_result = self._decode_command_result(result)
        project = self.project_registry.register_project(request, command_result)
        return {"project": project.to_dict()}

    def rpc_list_projects(self, params: dict[str, Any]) -> dict[str, Any]:
        _ = params
        projects = [item.to_dict() for item in self.project_registry.list_projects()]
        return {"projects": projects}

    def rpc_get_project(self, params: dict[str, Any]) -> dict[str, Any]:
        project_id = str(params.get("id", "")).strip()
        if not project_id:
            raise JSONRPCError(-32602, "get_project requires id.")
        project = self.project_registry.get_project(project_id)
        if project is None:
            raise KeyError(f"Unknown project id: {project_id}")
        latest_session = self.session_registry.latest_session(project_id)
        return {
            "project": project.to_dict(),
            "latest_session": latest_session.to_dict() if latest_session else None,
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
        session = self.session_registry.start_session(project_id, title)
        self.project_registry.increment_session_count(project_id)
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


def run_runtime_server(socket_path: str, *, base_dir: Path | None = None) -> None:
    runtime = AgentAppFlowRuntime(base_dir=base_dir)
    socket_file = Path(socket_path).expanduser().resolve()
    socket_file.parent.mkdir(parents=True, exist_ok=True)

    if socket_file.exists():
        socket_file.unlink()

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(str(socket_file))
        os.chmod(socket_file, 0o600)
        server.listen()

        while True:
            connection, _ = server.accept()
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
