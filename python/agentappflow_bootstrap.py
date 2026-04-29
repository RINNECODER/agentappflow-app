#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIRECTORY = os.path.dirname(os.path.abspath(__file__))
MODULE_DIRECTORIES = [
    SCRIPT_DIRECTORY,
    os.path.join(SCRIPT_DIRECTORY, "agentappflow_core"),
]

for directory in MODULE_DIRECTORIES:
    if directory not in sys.path:
        sys.path.insert(0, directory)

from bootstrap import BootstrapError, BootstrapRequest, CommandResult, bootstrap_project, load_request_from_json
from runtime import AgentAppFlowRuntime, JSONRPCError, run_runtime_server

EXIT_SUCCESS = 0
EXIT_VALIDATION_ERROR = 1
EXIT_RUNTIME_ERROR = 2


class CLIValidationError(Exception):
    """Raised when CLI inputs are invalid."""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="AgentAppFlow local runtime utilities")
    parser.add_argument("--verbose", action="store_true", help="Enable debug output")
    subparsers = parser.add_subparsers(dest="command", required=True)

    serve_parser = subparsers.add_parser("serve", help="Start the local JSON-RPC runtime server")
    serve_parser.add_argument("--socket", required=True, help="Unix domain socket path")

    bootstrap_parser = subparsers.add_parser("bootstrap", help="Initialize .agentappflow/ in a target repository")
    add_request_input_arguments(bootstrap_parser)
    bootstrap_parser.add_argument("--force", action="store_true", help="Rewrite generated files even if unchanged")

    register_parser = subparsers.add_parser("register", help="Register a bootstrapped project in the runtime registry")
    add_request_input_arguments(register_parser)

    list_parser = subparsers.add_parser("list", help="List registered projects")
    list_parser.add_argument("--format", choices=("json", "table"), default="json")

    status_parser = subparsers.add_parser("status", help="Show runtime health")
    status_parser.add_argument("--format", choices=("json", "table"), default="json")

    session_parser = subparsers.add_parser("session", help="Session commands")
    session_subparsers = session_parser.add_subparsers(dest="session_command", required=True)

    session_start_parser = session_subparsers.add_parser("start", help="Start a session for a project")
    session_start_parser.add_argument("project_id", help="Registered project ID")
    session_start_parser.add_argument("--title", default="", help="Optional session title")

    session_list_parser = session_subparsers.add_parser("list", help="List sessions for a project")
    session_list_parser.add_argument("project_id", help="Registered project ID")
    session_list_parser.add_argument("--format", choices=("json", "table"), default="json")

    return parser


def add_request_input_arguments(parser: argparse.ArgumentParser) -> None:
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--input", help="Path to a JSON request file")
    group.add_argument("--stdin", action="store_true", help="Read the JSON request from stdin")


def debug(message: str, *, verbose: bool) -> None:
    if verbose:
        print(message, file=sys.stderr, flush=True)


def load_request_from_stdin() -> BootstrapRequest:
    raw_payload = sys.stdin.read()
    if not raw_payload.strip():
        raise CLIValidationError("Expected JSON bootstrap request on stdin.")
    payload = json.loads(raw_payload)
    if not isinstance(payload, dict):
        raise CLIValidationError("Bootstrap request JSON must be an object.")
    return BootstrapRequest.from_dict(payload)


def load_request_from_args(args: argparse.Namespace) -> BootstrapRequest:
    if getattr(args, "stdin", False):
        return load_request_from_stdin()
    input_path = getattr(args, "input", "")
    if not input_path:
        raise CLIValidationError("Missing bootstrap request source.")
    return load_request_from_json(input_path)


def emit_json(payload: Any) -> None:
    print(json.dumps(payload, indent=2, sort_keys=True))


def render_projects_table(projects: list[dict[str, Any]]) -> str:
    if not projects:
        return "No registered projects."
    lines = ["ID                                 NAME                 TYPE           SESSIONS  PATH"]
    for project in projects:
        lines.append(
            f"{project['id'][:32]:32}  "
            f"{project['project_name'][:20]:20}  "
            f"{project['project_type'][:13]:13}  "
            f"{str(project.get('session_count', 0)):8}  "
            f"{project['project_path']}"
        )
    return "\n".join(lines)


def render_sessions_table(sessions: list[dict[str, Any]]) -> str:
    if not sessions:
        return "No sessions recorded."
    lines = ["ID                                 STATUS       STARTED AT                        TITLE"]
    for session in sessions:
        lines.append(
            f"{session['id'][:32]:32}  "
            f"{session['status'][:10]:10}  "
            f"{session['started_at'][:32]:32}  "
            f"{session['title']}"
        )
    return "\n".join(lines)


def render_status_table(payload: dict[str, Any]) -> str:
    return "\n".join(
        [
            f"Status:           {payload['status']}",
            f"Version:          {payload['version']}",
            f"Python:           {payload['python_version']}",
            f"Uptime (seconds): {payload['uptime_seconds']}",
            f"Project count:    {payload['project_count']}",
            f"Registry path:    {payload['registry_path']}",
            f"Socket path:      {payload.get('socket_path') or '-'}",
        ]
    )


def handle_bootstrap(args: argparse.Namespace) -> int:
    request = load_request_from_args(args)
    debug(f"Bootstrapping project at {request.project_root}", verbose=args.verbose)
    result = bootstrap_project(request, force=bool(args.force))
    emit_json(result.to_dict())
    return EXIT_SUCCESS


def handle_register(args: argparse.Namespace) -> int:
    request = load_request_from_args(args)
    debug(f"Registering project at {request.project_root}", verbose=args.verbose)
    runtime = AgentAppFlowRuntime()
    project = runtime.rpc_register_project(request.to_dict())
    emit_json({"project": project})
    return EXIT_SUCCESS


def handle_list(args: argparse.Namespace) -> int:
    runtime = AgentAppFlowRuntime()
    projects = runtime.rpc_list_projects({})
    if args.format == "json":
        emit_json(projects)
    else:
        print(render_projects_table(projects))
    return EXIT_SUCCESS


def handle_status(args: argparse.Namespace) -> int:
    runtime = AgentAppFlowRuntime()
    status = runtime.rpc_health_check({})
    if args.format == "json":
        emit_json(status)
    else:
        print(render_status_table(status))
    return EXIT_SUCCESS


def handle_session_start(args: argparse.Namespace) -> int:
    runtime = AgentAppFlowRuntime()
    result = runtime.rpc_start_session({"project_id": args.project_id, "title": args.title})
    emit_json(result)
    return EXIT_SUCCESS


def handle_session_list(args: argparse.Namespace) -> int:
    runtime = AgentAppFlowRuntime()
    sessions = [item.to_dict() for item in runtime.session_registry.list_sessions(project_id=args.project_id)]
    if args.format == "json":
        emit_json(sessions)
    else:
        print(render_sessions_table(sessions))
    return EXIT_SUCCESS


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "serve":
            debug(f"Starting runtime server on {args.socket}", verbose=args.verbose)
            run_runtime_server(args.socket, verbose=args.verbose)
            return EXIT_SUCCESS
        if args.command == "bootstrap":
            return handle_bootstrap(args)
        if args.command == "register":
            return handle_register(args)
        if args.command == "list":
            return handle_list(args)
        if args.command == "status":
            return handle_status(args)
        if args.command == "session" and args.session_command == "start":
            return handle_session_start(args)
        if args.command == "session" and args.session_command == "list":
            return handle_session_list(args)
        raise CLIValidationError(f"Unknown command: {args.command}")
    except (BootstrapError, CLIValidationError, json.JSONDecodeError) as error:
        emit_json(
            CommandResult(
                ok=False,
                message=str(error),
                created=[],
                skipped=[],
                warnings=[],
            ).to_dict()
        )
        return EXIT_VALIDATION_ERROR
    except (JSONRPCError, KeyError, OSError) as error:
        emit_json(
            {
                "ok": False,
                "message": str(error),
                "category": "runtime_error",
            }
        )
        return EXIT_RUNTIME_ERROR
    except Exception as error:  # pragma: no cover - defensive top-level handling
        emit_json(
            {
                "ok": False,
                "message": f"Unexpected runtime failure: {error}",
                "category": "runtime_error",
            }
        )
        return EXIT_RUNTIME_ERROR


if __name__ == "__main__":
    sys.exit(main())
