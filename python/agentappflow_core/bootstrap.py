from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

VALID_PROJECT_TYPES = {"ios_app", "macos_app", "cross_platform_app", "library"}
VALID_PLATFORMS = {"ios", "macos", "library"}
VALID_AGENT_TOOLS = {"codex", "claude_code"}
VALID_APPROVAL_MODES = {"manual", "propose", "auto"}
VALID_IMPROVEMENT_MODES = {"observe", "propose", "auto"}


class BootstrapError(Exception):
    """Raised when bootstrap validation or file creation fails."""


@dataclass(frozen=True)
class BootstrapRequest:
    project_name: str
    project_description: str
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
            project_description=str(payload.get("project_description", "")),
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

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2, sort_keys=True)


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
    description_block = render_yaml_multiline_field("project_description", request.project_description)
    return f"""project_type: {request.project_type}
project_name: {request.project_name}
{description_block}
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


def render_yaml_multiline_field(key: str, value: str) -> str:
    if not value.strip():
        return f"{key}: \"\""
    indented_lines = "\n".join(f"  {line}" for line in value.strip().splitlines())
    return f"{key}: |-\n{indented_lines}"


def render_rules_markdown(request: BootstrapRequest) -> str:
    project_brief = ""
    if request.project_description.strip():
        project_brief = f"\n## Project Brief\n{request.project_description.strip()}\n"

    return f"""# Core Rules

## Project Identity
- Project name: {request.project_name}
- Project type: {request.project_type}
- Platforms: {", ".join(request.platforms)}
- Agent tools: {", ".join(request.agent_tools)}
{project_brief}

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
    context_line = (
        "- project brief lives in `.agentappflow/project.yaml` under `project_description`\n"
        if request.project_description.strip()
        else ""
    )
    return f"""# AgentAppFlow Adapter

Framework root: `.agentappflow/`

Start here:
- `.agentappflow/project.yaml`
- `.agentappflow/rules/core-rules.md`
- `.agentappflow/templates/task-template.md`
- `.agentappflow/templates/retrospective-template.md`
{context_line}

Project policy:
- approval mode: `{request.approval_mode}`
- improvement mode: `{request.improvement_mode}`
- sessions live in `.agentappflow/sessions/`
- proposals live in `.agentappflow/proposals/`
"""


def render_claude_md(request: BootstrapRequest) -> str:
    context_line = (
        "- use `project_description` in `.agentappflow/project.yaml` as first-pass product context\n"
        if request.project_description.strip()
        else ""
    )
    return f"""# AgentAppFlow Adapter

Use the project framework stored in `.agentappflow/`.

Read before acting:
- `.agentappflow/project.yaml`
- `.agentappflow/rules/core-rules.md`
- `.agentappflow/templates/task-template.md`
- `.agentappflow/templates/retrospective-template.md`
{context_line}

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
