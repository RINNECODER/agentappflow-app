from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

try:
    from .bootstrap import BootstrapRequest, CommandResult
except ImportError:  # pragma: no cover - bundled resource import path
    from bootstrap import BootstrapRequest, CommandResult


def current_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def default_data_directory() -> Path:
    runtime_home = os.environ.get("AGENTAPPFLOW_RUNTIME_HOME", "").strip()
    if runtime_home:
        return Path(runtime_home).expanduser().resolve()
    return Path.home() / "Library" / "Application Support" / "AgentAppFlow"


@dataclass
class RegisteredProject:
    id: str
    project_name: str
    project_description: str
    project_path: str
    project_type: str
    platforms: list[str]
    agent_tools: list[str]
    approval_mode: str
    improvement_mode: str
    created_items: list[str]
    skipped_items: list[str]
    registered_at: str
    updated_at: str
    last_bootstrapped_at: str
    session_count: int

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "RegisteredProject":
        return cls(
            id=str(payload["id"]),
            project_name=str(payload["project_name"]),
            project_description=str(payload.get("project_description", "")),
            project_path=str(payload["project_path"]),
            project_type=str(payload["project_type"]),
            platforms=[str(item) for item in payload.get("platforms", [])],
            agent_tools=[str(item) for item in payload.get("agent_tools", [])],
            approval_mode=str(payload["approval_mode"]),
            improvement_mode=str(payload["improvement_mode"]),
            created_items=[str(item) for item in payload.get("created_items", [])],
            skipped_items=[str(item) for item in payload.get("skipped_items", [])],
            registered_at=str(payload["registered_at"]),
            updated_at=str(payload["updated_at"]),
            last_bootstrapped_at=str(payload["last_bootstrapped_at"]),
            session_count=int(payload.get("session_count", 0)),
        )

    @classmethod
    def from_bootstrap(
        cls,
        request: BootstrapRequest,
        result: CommandResult,
        *,
        existing_id: str | None = None,
        registered_at: str | None = None,
        session_count: int = 0,
    ) -> "RegisteredProject":
        timestamp = current_timestamp()
        return cls(
            id=existing_id or uuid4().hex,
            project_name=request.project_name,
            project_description=request.project_description,
            project_path=str(request.project_root),
            project_type=request.project_type,
            platforms=list(request.platforms),
            agent_tools=list(request.agent_tools),
            approval_mode=request.approval_mode,
            improvement_mode=request.improvement_mode,
            created_items=list(result.created),
            skipped_items=list(result.skipped),
            registered_at=registered_at or timestamp,
            updated_at=timestamp,
            last_bootstrapped_at=timestamp,
            session_count=session_count,
        )


@dataclass
class SessionRecord:
    id: str
    project_id: str
    title: str
    status: str
    created_at: str
    started_at: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "SessionRecord":
        return cls(
            id=str(payload["id"]),
            project_id=str(payload["project_id"]),
            title=str(payload["title"]),
            status=str(payload["status"]),
            created_at=str(payload["created_at"]),
            started_at=str(payload["started_at"]),
        )

    @classmethod
    def create(cls, project_id: str, title: str) -> "SessionRecord":
        timestamp = current_timestamp()
        return cls(
            id=uuid4().hex,
            project_id=project_id,
            title=title,
            status="running",
            created_at=timestamp,
            started_at=timestamp,
        )


class JSONListStore:
    def __init__(self, path: Path) -> None:
        self.path = path

    def load(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        payload = json.loads(self.path.read_text(encoding="utf-8"))
        if not isinstance(payload, list):
            raise ValueError(f"Expected list payload in {self.path}")
        return payload

    def save(self, records: list[dict[str, Any]]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(records, indent=2, sort_keys=True), encoding="utf-8")


class ProjectRegistry:
    def __init__(self, base_dir: Path | None = None) -> None:
        self.base_dir = (base_dir or default_data_directory()).expanduser().resolve()
        self.store = JSONListStore(self.base_dir / "runtime" / "projects.json")

    def list_projects(self) -> list[RegisteredProject]:
        records = [RegisteredProject.from_dict(item) for item in self.store.load()]
        return sorted(records, key=lambda item: item.updated_at, reverse=True)

    def get_project(self, project_id: str) -> RegisteredProject | None:
        for project in self.list_projects():
            if project.id == project_id:
                return project
        return None

    def get_project_by_path(self, project_path: str) -> RegisteredProject | None:
        normalized_path = str(Path(project_path).expanduser().resolve())
        for project in self.list_projects():
            if str(Path(project.project_path).expanduser().resolve()) == normalized_path:
                return project
        return None

    def save_project(self, project: RegisteredProject) -> RegisteredProject:
        records = self.list_projects()
        updated: list[RegisteredProject] = [item for item in records if item.id != project.id]
        updated.append(project)
        self.store.save([item.to_dict() for item in updated])
        return project

    def register_project(
        self,
        request: BootstrapRequest,
        result: CommandResult,
    ) -> RegisteredProject:
        existing = self.get_project_by_path(request.project_path)
        project = RegisteredProject.from_bootstrap(
            request,
            result,
            existing_id=existing.id if existing else None,
            registered_at=existing.registered_at if existing else None,
            session_count=existing.session_count if existing else 0,
        )
        return self.save_project(project)

    def increment_session_count(self, project_id: str) -> RegisteredProject:
        project = self.get_project(project_id)
        if project is None:
            raise KeyError(f"Unknown project id: {project_id}")
        project.session_count += 1
        project.updated_at = current_timestamp()
        return self.save_project(project)


class SessionRegistry:
    def __init__(self, base_dir: Path | None = None) -> None:
        self.base_dir = (base_dir or default_data_directory()).expanduser().resolve()
        self.store = JSONListStore(self.base_dir / "runtime" / "sessions.json")

    def list_sessions(self, project_id: str | None = None) -> list[SessionRecord]:
        records = [SessionRecord.from_dict(item) for item in self.store.load()]
        if project_id is not None:
            records = [item for item in records if item.project_id == project_id]
        return sorted(records, key=lambda item: item.started_at, reverse=True)

    def latest_session(self, project_id: str) -> SessionRecord | None:
        sessions = self.list_sessions(project_id=project_id)
        return sessions[0] if sessions else None

    def start_session(self, project_id: str, title: str) -> SessionRecord:
        records = self.list_sessions()
        session = SessionRecord.create(project_id=project_id, title=title)
        records.append(session)
        self.store.save([item.to_dict() for item in records])
        return session
