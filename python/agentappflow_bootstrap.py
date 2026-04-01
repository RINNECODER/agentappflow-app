#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys

SCRIPT_DIRECTORY = os.path.dirname(os.path.abspath(__file__))
MODULE_DIRECTORIES = [
    SCRIPT_DIRECTORY,
    os.path.join(SCRIPT_DIRECTORY, "agentappflow_core"),
]

for directory in MODULE_DIRECTORIES:
    if directory not in sys.path:
        sys.path.insert(0, directory)

from bootstrap import BootstrapError, BootstrapRequest, CommandResult, bootstrap_project, load_request_from_json
from runtime import run_runtime_server


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="AgentAppFlow local runtime utilities")
    subparsers = parser.add_subparsers(dest="command", required=True)

    bootstrap_parser = subparsers.add_parser(
        "bootstrap_project", help="Initialize .agentappflow/ in a target repository"
    )
    bootstrap_parser.add_argument("--input", required=True, help="Path to a JSON request file")
    bootstrap_parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite generated files if they already exist",
    )

    serve_parser = subparsers.add_parser("serve", help="Start the local JSON-RPC runtime server")
    serve_parser.add_argument("--socket", required=True, help="Unix domain socket path")

    return parser


def handle_bootstrap_project(input_path: str, *, force: bool) -> int:
    try:
        request = load_request_from_json(input_path)
        result = bootstrap_project(request, force=force)
        print(result.to_json())
        return 0
    except BootstrapError as error:
        print(
            CommandResult(
                ok=False,
                message=str(error),
                created=[],
                skipped=[],
            ).to_json()
        )
        return 1
    except Exception as error:  # pragma: no cover - defensive top-level handling
        print(
            CommandResult(
                ok=False,
                message=f"Unexpected bootstrap failure: {error}",
                created=[],
                skipped=[],
            ).to_json()
        )
        return 1


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "bootstrap_project":
        return handle_bootstrap_project(args.input, force=args.force)
    if args.command == "serve":
        run_runtime_server(args.socket)
        return 0

    parser.error(f"Unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
