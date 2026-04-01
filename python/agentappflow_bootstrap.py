#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

VALID_PROJECT_TYPES = {"ios_app", "macos_app", "cross_platform_app", "library"}
VALID_PLATFORMS = {"ios", "macos"}
VALID_AGENT_TOOLS = {"codex", "claude_code"}
VALID_APPROVAL_MODES = {"manual", "propose", "auto"}
VALID_IMPROVEMENT_MODES = {"observe", "propose", "auto"}


class BootstrapError(Exception):
    """Raised when bootstrap validation or file creation fails."""


@dataclass(frozen=True)
class BootstrapRequest:
    project_name: str
    project_path: str
    project_type: str
    platforms: list[str]
    agent_tools: list[str]
    approval_mode: str
    improvement_mode: str
    memory_mode: str = "local_repo"

    @property
    def project_root(self) -> Path:
        return Path(self.project_path).expanduser().resolve()

    def validate(self) -> None:
        if not self.project_name.strip():
            raise BootstrapError("project_name is required.")
        if not self.project_path.strip():
            raise BootstrapError("project_path is required.")
        if self.project_type not in VALID_PROJECT_TYPES:
            raise BootstrapError(f"Unsupported project_type: {self.project_type}")
        if not self.platforms:
            raise BootstrapError("At least one platform is required.")
        if unknown_platforms := sorted(set(self.platforms) - VALID_PLATFORMS):
            raise BootstrapError(f"Unsupported platforms: {', '.join(unknown_platforms)}")
        if not self.agent_tools:
            raise BootstrapError("At least one agent tool is required.")
        if unknown_tools := sorted(set(self.agent_tools) - VALID_AGENT_TOOLS):
            raise BootstrapError(f"Unsupported agent_tools: {', '.join(unknown_tools)}")
        if self.approval_mode not in VALID_APPROVAL_MODES:
            raise BootstrapError(f"Unsupported approval_mode: {self.approval_mode}")
        if self.improvement_mode not in VALID_IMPROVEMENT_MODES:
            raise BootstrapError(f"Unsupported improvement_mode: {self.improvement_mode}")
        if self.memory_mode != "local_repo":
            raise BootstrapError("memory_mode must be 'local_repo' for this milestone.")
        if not self.project_root.exists():
            raise BootstrapError(f"Project path does not exist: {self.project_root}")
        if not self.project_root.is_dir():
            raise BootstrapError(f"Project path is not a directory: {self.project_root}")
        if not is_git_repo(self.project_root):
            raise BootstrapError(
                "Project path must point to a git repository root for bootstrap initialization."
            )

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "BootstrapRequest":
        return cls(
            project_name=str(payload.get("project_name", "")),
            project_path=str(payload.get("project_path", "")),
            project_type=str(payload.get("project_type", "")),
            platforms=[str(item) for item in payload.get("platforms", [])],
            agent_tools=[str(item) for item in payload.get("agent_tools", [])],
            approval_mode=str(payload.get("approval_mode", "")),
            improvement_mode=str(payload.get("improvement_mode", "")),
            memory_mode=str(payload.get("memory_mode", "local_repo")),
        )


@dataclass
class CommandResult:
    ok: bool
    message: str
    created: list[str]
    skipped: list[str]

    def to_json(self) -> str:
        return json.dumps(
            {
                "ok": self.ok,
                "message": self.message,
                "created": self.created,
                "skipped": self.skipped,
            },
            indent=2,
            sort_keys=True,
        )


def is_git_repo(path: Path) -> bool:
    return (path / ".git").exists()


def relative_path(path: Path, root: Path, trailing_slash: bool = False) -> str:
    rel = path.relative_to(root).as_posix()
    if trailing_slash and not rel.endswith("/"):
        return f"{rel}/"
    return rel


def ensure_directory(path: Path, root: Path, created: list[str], skipped: list[str]) -> None:
    if path.exists():
        skipped.append(relative_path(path, root, trailing_slash=True))
        return
    path.mkdir(parents=True, exist_ok=True)
    created.append(relative_path(path, root, trailing_slash=True))


def write_text_file(
    path: Path,
    contents: str,
    root: Path,
    created: list[str],
    skipped: list[str],
    *,
    force: bool,
) -> None:
    if path.exists() and not force:
        skipped.append(relative_path(path, root))
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8")
    created.append(relative_path(path, root))


def render_project_yaml(request: BootstrapRequest) -> str:
    platform_lines = "\n".join(f"  - {platform}" for platform in request.platforms)
    tool_lines = "\n".join(f"  - {tool}" for tool in request.agent_tools)
    return f"""project_type: {request.project_type}
project_name: {request.project_name}
platforms:
{platform_lines}
tech_stack:
  ui: swift
  orchestration: python
  execution: rust
agent_tools:
{tool_lines}
approval_mode: {request.approval_mode}
memory_mode: {request.memory_mode}
improvement_mode: {request.improvement_mode}
"""


def render_rules_markdown(request: BootstrapRequest) -> str:
    return f"""# Core Rules

## Project Identity
- Project name: {request.project_name}
- Project type: {request.project_type}
- Platforms: {", ".join(request.platforms)}
- Agent tools: {", ".join(request.agent_tools)}

## Operating Model
- Treat `.agentappflow/` as the framework root for this repository.
- Keep canonical memory, framework rules, and templates human-readable.
- Prefer incremental, reviewable changes over broad rewrites.
- Preserve local-only execution; do not introduce backend dependencies without explicit approval.

## Runtime Boundaries
- Swift is the user-facing app shell.
- Python is the orchestration layer for project bootstrap and future memory workflows.
- Rust is a deferred execution guardrail layer for a later milestone.
"""


def render_task_template() -> str:
    return """# Task Template

## Goal
- Describe the user-visible outcome.

## Constraints
- Note repo rules, approval expectations, and important boundaries.

## Context To Reuse
- Relevant sessions:
- Relevant retrospectives:
- Relevant framework rules:

## Completion Check
- What should be true when the task is done?
"""


def render_retrospective_template() -> str:
    return """# Retrospective Template

## What succeeded?

## What created friction?

## What should change in the framework?

## Confidence

## Evidence
"""


def render_agents_md(request: BootstrapRequest) -> str:
    return f"""# AgentAppFlow Adapter

Framework root: `.agentappflow/`

Start here:
- `.agentappflow/project.yaml`
- `.agentappflow/rules/core-rules.md`
- `.agentappflow/templates/task-template.md`
- `.agentappflow/templates/retrospective-template.md`

Project policy:
- approval mode: `{request.approval_mode}`
- improvement mode: `{request.improvement_mode}`
- sessions live in `.agentappflow/sessions/`
- proposals live in `.agentappflow/proposals/`
"""


def render_claude_md(request: BootstrapRequest) -> str:
    return f"""# AgentAppFlow Adapter

Use the project framework stored in `.agentappflow/`.

Read before acting:
- `.agentappflow/project.yaml`
- `.agentappflow/rules/core-rules.md`
- `.agentappflow/templates/task-template.md`
- `.agentappflow/templates/retrospective-template.md`

Current modes:
- approval mode: `{request.approval_mode}`
- improvement mode: `{request.improvement_mode}`
"""


def bootstrap_project(request: BootstrapRequest, *, force: bool = False) -> CommandResult:
    request.validate()

    root = request.project_root
    framework_root = root / ".agentappflow"
    created: list[str] = []
    skipped: list[str] = []

    directories = [
        framework_root,
        framework_root / "rules",
        framework_root / "templates",
        framework_root / "sessions",
        framework_root / "retros",
        framework_root / "proposals",
        framework_root / "cache",
    ]

    for directory in directories:
        ensure_directory(directory, root, created, skipped)

    write_text_file(
        framework_root / "project.yaml",
        render_project_yaml(request),
        root,
        created,
        skipped,
        force=force,
    )
    write_text_file(
        framework_root / "rules" / "core-rules.md",
        render_rules_markdown(request),
        root,
        created,
        skipped,
        force=force,
    )
    write_text_file(
        framework_root / "templates" / "task-template.md",
        render_task_template(),
        root,
        created,
        skipped,
        force=force,
    )
    write_text_file(
        framework_root / "templates" / "retrospective-template.md",
        render_retrospective_template(),
        root,
        created,
        skipped,
        force=force,
    )
    write_text_file(
        root / "AGENTS.md",
        render_agents_md(request),
        root,
        created,
        skipped,
        force=force,
    )
    write_text_file(
        root / "CLAUDE.md",
        render_claude_md(request),
        root,
        created,
        skipped,
        force=force,
    )

    return CommandResult(
        ok=True,
        message=f"Initialized AgentAppFlow in {root.name}.",
        created=created,
        skipped=skipped,
    )


def load_request_from_json(path: str) -> BootstrapRequest:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    return BootstrapRequest.from_dict(payload)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="AgentAppFlow local bootstrap utilities")
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

    parser.error(f"Unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
