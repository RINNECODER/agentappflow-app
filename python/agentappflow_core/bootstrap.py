from __future__ import annotations

import json
import os
import subprocess
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

VALID_PROJECT_TYPES = {"ios_app", "macos_app", "cross_platform_app", "library"}
VALID_PLATFORMS = {"ios", "macos", "library"}
VALID_AGENT_TOOLS = {"codex", "claude_code"}
VALID_APPROVAL_MODES = {"manual", "observe", "propose", "auto"}
VALID_IMPROVEMENT_MODES = {"observe", "propose", "auto"}


class BootstrapError(Exception):
    """Raised when bootstrap validation or file generation fails."""


def normalize_approval_mode(value: str) -> str:
    return "observe" if value == "manual" else value


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

    def normalized(self) -> "BootstrapRequest":
        return BootstrapRequest(
            project_name=self.project_name.strip(),
            project_description=self.project_description.strip(),
            project_path=str(self.project_root),
            project_type=self.project_type.strip(),
            platforms=[item.strip() for item in self.platforms if item.strip()],
            agent_tools=[item.strip() for item in self.agent_tools if item.strip()],
            approval_mode=normalize_approval_mode(self.approval_mode.strip()),
            improvement_mode=self.improvement_mode.strip(),
            memory_mode=self.memory_mode.strip() or "local_repo",
        )

    def validate(self) -> None:
        normalized = self.normalized()

        if not normalized.project_name:
            raise BootstrapError("project_name is required.")
        if not normalized.project_path:
            raise BootstrapError("project_path is required.")
        if normalized.project_type not in VALID_PROJECT_TYPES:
            raise BootstrapError(f"Unsupported project_type: {normalized.project_type}")
        if not normalized.platforms:
            raise BootstrapError("At least one platform is required.")
        if any(not item for item in normalized.platforms):
            raise BootstrapError("platforms may not contain empty values.")
        if unknown_platforms := sorted(set(normalized.platforms) - VALID_PLATFORMS):
            raise BootstrapError(f"Unsupported platforms: {', '.join(unknown_platforms)}")
        if not normalized.agent_tools:
            raise BootstrapError("At least one agent tool is required.")
        if any(not item for item in normalized.agent_tools):
            raise BootstrapError("agent_tools may not contain empty values.")
        if unknown_tools := sorted(set(normalized.agent_tools) - VALID_AGENT_TOOLS):
            raise BootstrapError(f"Unsupported agent_tools: {', '.join(unknown_tools)}")
        if normalized.approval_mode not in VALID_APPROVAL_MODES:
            raise BootstrapError(f"Unsupported approval_mode: {normalized.approval_mode}")
        if normalized.improvement_mode not in VALID_IMPROVEMENT_MODES:
            raise BootstrapError(f"Unsupported improvement_mode: {normalized.improvement_mode}")
        if normalized.memory_mode != "local_repo":
            raise BootstrapError("memory_mode must be 'local_repo' for this milestone.")
        if not normalized.project_root.exists():
            raise BootstrapError(f"Project path does not exist: {normalized.project_root}")
        if not normalized.project_root.is_dir():
            raise BootstrapError(f"Project path is not a directory: {normalized.project_root}")
        if not is_git_repo(normalized.project_root):
            raise BootstrapError(
                "Project path must point to a git repository root for bootstrap initialization."
            )

    def to_dict(self) -> dict[str, Any]:
        return asdict(self.normalized())

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
class BootstrapResult:
    ok: bool
    message: str
    created: list[str]
    skipped: list[str]
    warnings: list[str]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2, sort_keys=True)


# Backward-compatible name for the Swift shell and older imports.
CommandResult = BootstrapResult


def is_git_repo(path: Path) -> bool:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=path,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return False
    try:
        repo_root = Path(result.stdout.strip()).expanduser().resolve()
    except OSError:
        return False
    return repo_root == path.resolve()


def relative_path(path: Path, root: Path, trailing_slash: bool = False) -> str:
    rel = path.relative_to(root).as_posix()
    if trailing_slash and not rel.endswith("/"):
        return f"{rel}/"
    return rel


def atomic_write_text(path: Path, contents: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temp_path_string = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    temp_path = Path(temp_path_string)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as temp_file:
            temp_file.write(contents)
            temp_file.flush()
            os.fsync(temp_file.fileno())
        os.replace(temp_path, path)
    except Exception:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass
        raise


def ensure_directory(path: Path, root: Path, created: list[str], skipped: list[str]) -> None:
    if path.exists():
        if not path.is_dir():
            raise BootstrapError(f"Expected directory but found file at {path}")
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
    warnings: list[str],
    *,
    force: bool,
) -> None:
    relative = relative_path(path, root)
    if path.exists():
        if path.is_dir():
            raise BootstrapError(f"Expected file but found directory at {path}")
        if not force:
            if path.read_text(encoding="utf-8") == contents:
                skipped.append(relative)
                return
            skipped.append(relative)
            warnings.append(f"Skipped divergent existing file without force: {relative}")
            return
    atomic_write_text(path, contents)
    created.append(relative)


def render_yaml_multiline_field(key: str, value: str) -> str:
    if not value.strip():
        return f'{key}: ""'
    indented_lines = "\n".join(f"  {line}" for line in value.strip().splitlines())
    return f"{key}: |-\n{indented_lines}"


def render_project_yaml(request: BootstrapRequest) -> str:
    normalized = request.normalized()
    platform_lines = "\n".join(f"  - {platform}" for platform in normalized.platforms)
    tool_lines = "\n".join(f"  - {tool}" for tool in normalized.agent_tools)
    description_block = render_yaml_multiline_field("project_description", normalized.project_description)
    return f"""project_type: {normalized.project_type}
project_name: {normalized.project_name}
{description_block}
platforms:
{platform_lines}
tech_stack:
  ui: swift
  orchestration: python
  execution: rust
agent_tools:
{tool_lines}
approval_mode: {normalized.approval_mode}
memory_mode: {normalized.memory_mode}
improvement_mode: {normalized.improvement_mode}
"""


def render_rules_markdown(request: BootstrapRequest) -> str:
    normalized = request.normalized()
    description_section = ""
    if normalized.project_description:
        description_section = f"\n## Project Brief\n{normalized.project_description}\n"

    return f"""# Default Rules

## Project Identity
- Project name: {normalized.project_name}
- Project type: {normalized.project_type}
- Platforms: {", ".join(normalized.platforms)}
- Agent tools: {", ".join(normalized.agent_tools)}
{description_section}

## Framework Boundaries
- `.agentappflow/` is the repo-local framework contract for this repository.
- Keep canonical framework state human-readable and reviewable.
- Prefer incremental, well-scoped changes over broad rewrites.
- Treat unrelated user source code as out of scope unless the active task explicitly requires it.

## Runtime Model
- Swift is the control-center shell.
- Python owns orchestration, retrieval, and framework generation.
- Rust is reserved for guarded execution in later milestones.
"""


def render_session_template() -> str:
    return """# Session Template

## Goal
- Describe the user-visible outcome for this session.

## Constraints
- Note repo rules, approval expectations, and important technical boundaries.

## Evidence
- Relevant files, runtime output, or validation artifacts.

## Exit Check
- What must be true before this session is considered complete?
"""


def render_retro_template() -> str:
    return """# Retro Template

## What succeeded?

## What created friction?

## What should change in the framework?

## Confidence

## Evidence
"""


def render_agents_md(request: BootstrapRequest) -> str:
    normalized = request.normalized()
    return f"""# AgentAppFlow Adapter

Framework root: `.agentappflow/`

Read before acting:
- `.agentappflow/project.yaml`
- `.agentappflow/rules/default.md`
- `.agentappflow/templates/session.md`
- `.agentappflow/templates/retro.md`

Current policy:
- approval mode: `{normalized.approval_mode}`
- improvement mode: `{normalized.improvement_mode}`
"""


def render_claude_md(request: BootstrapRequest) -> str:
    normalized = request.normalized()
    return f"""# AgentAppFlow Adapter

Use the project framework stored in `.agentappflow/`.

Read before acting:
- `.agentappflow/project.yaml`
- `.agentappflow/rules/default.md`
- `.agentappflow/templates/session.md`
- `.agentappflow/templates/retro.md`

Current policy:
- approval mode: `{normalized.approval_mode}`
- improvement mode: `{normalized.improvement_mode}`
"""


def validate_bootstrap_exists(project_root: Path) -> None:
    framework_root = project_root / ".agentappflow"
    required_files = [
        framework_root / "project.yaml",
        framework_root / "rules" / "default.md",
        framework_root / "templates" / "session.md",
        framework_root / "templates" / "retro.md",
        project_root / "AGENTS.md",
        project_root / "CLAUDE.md",
    ]
    missing = [str(path) for path in required_files if not path.exists()]
    if missing:
        raise BootstrapError(
            "Project is not bootstrapped. Missing required files: " + ", ".join(missing)
        )


def bootstrap_project(request: BootstrapRequest, *, force: bool = False) -> BootstrapResult:
    request.validate()
    normalized = request.normalized()

    root = normalized.project_root
    framework_root = root / ".agentappflow"
    created: list[str] = []
    skipped: list[str] = []
    warnings: list[str] = []

    if request.approval_mode.strip() == "manual":
        warnings.append("approval_mode 'manual' is deprecated; normalized to 'observe'.")

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
        render_project_yaml(normalized),
        root,
        created,
        skipped,
        warnings,
        force=force,
    )
    write_text_file(
        framework_root / "rules" / "default.md",
        render_rules_markdown(normalized),
        root,
        created,
        skipped,
        warnings,
        force=force,
    )
    write_text_file(
        framework_root / "templates" / "session.md",
        render_session_template(),
        root,
        created,
        skipped,
        warnings,
        force=force,
    )
    write_text_file(
        framework_root / "templates" / "retro.md",
        render_retro_template(),
        root,
        created,
        skipped,
        warnings,
        force=force,
    )
    write_text_file(
        root / "AGENTS.md",
        render_agents_md(normalized),
        root,
        created,
        skipped,
        warnings,
        force=force,
    )
    write_text_file(
        root / "CLAUDE.md",
        render_claude_md(normalized),
        root,
        created,
        skipped,
        warnings,
        force=force,
    )

    return BootstrapResult(
        ok=True,
        message=f"Bootstrapped AgentAppFlow in {root.name}.",
        created=created,
        skipped=skipped,
        warnings=warnings,
    )


def load_request_from_json(path: str) -> BootstrapRequest:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise BootstrapError("Bootstrap request JSON must be an object.")
    return BootstrapRequest.from_dict(payload)
