from __future__ import annotations

import json
import os
import re
import tempfile
import threading
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

try:
    from .bootstrap import BootstrapRequest, CommandResult
except ImportError:  # pragma: no cover - bundled resource import path
    from bootstrap import BootstrapRequest, CommandResult

PROJECT_REGISTRY_VERSION = 2
STORAGE_IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")


def current_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def default_data_directory() -> Path:
    runtime_home = os.environ.get("AGENTAPPFLOW_RUNTIME_HOME", "").strip()
    if runtime_home:
        return Path(runtime_home).expanduser().resolve()
    return Path.home() / "Library" / "Application Support" / "AgentAppFlow"


def validate_storage_identifier(value: str, label: str) -> str:
    identifier = str(value).strip()
    if not identifier:
        raise ValueError(f"{label} is required.")
    if "/" in identifier or "\\" in identifier or ".." in identifier:
        raise ValueError(f"{label} may not contain path separators or traversal.")
    if not STORAGE_IDENTIFIER_PATTERN.fullmatch(identifier):
        raise ValueError(f"{label} contains unsupported characters.")
    return identifier


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


def append_text_line(path: Path, line: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        with os.fdopen(descriptor, "a", encoding="utf-8") as handle:
            handle.write(line)
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        pass


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
    warnings: list[str]
    registered_at: str
    updated_at: str
    last_bootstrapped_at: str
    session_count: int
    latest_session_id: str | None = None
    latest_session_started_at: str | None = None
    latest_session_status: str | None = None
    latest_session_outcome: str | None = None
    latest_session_ended_at: str | None = None

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
            warnings=[str(item) for item in payload.get("warnings", [])],
            registered_at=str(payload["registered_at"]),
            updated_at=str(payload["updated_at"]),
            last_bootstrapped_at=str(payload["last_bootstrapped_at"]),
            session_count=int(payload.get("session_count", 0)),
            latest_session_id=payload.get("latest_session_id"),
            latest_session_started_at=payload.get("latest_session_started_at"),
            latest_session_status=payload.get("latest_session_status"),
            latest_session_outcome=payload.get("latest_session_outcome"),
            latest_session_ended_at=payload.get("latest_session_ended_at"),
        )

    @classmethod
    def from_bootstrap(
        cls,
        request: BootstrapRequest,
        result: CommandResult,
        *,
        existing: "RegisteredProject | None" = None,
    ) -> "RegisteredProject":
        normalized = request.normalized()
        timestamp = current_timestamp()
        return cls(
            id=existing.id if existing else uuid4().hex,
            project_name=normalized.project_name,
            project_description=normalized.project_description,
            project_path=str(normalized.project_root),
            project_type=normalized.project_type,
            platforms=list(normalized.platforms),
            agent_tools=list(normalized.agent_tools),
            approval_mode=normalized.approval_mode,
            improvement_mode=normalized.improvement_mode,
            created_items=list(result.created),
            skipped_items=list(result.skipped),
            warnings=list(result.warnings),
            registered_at=existing.registered_at if existing else timestamp,
            updated_at=timestamp,
            last_bootstrapped_at=timestamp,
            session_count=existing.session_count if existing else 0,
            latest_session_id=existing.latest_session_id if existing else None,
            latest_session_started_at=existing.latest_session_started_at if existing else None,
            latest_session_status=existing.latest_session_status if existing else None,
            latest_session_outcome=existing.latest_session_outcome if existing else None,
            latest_session_ended_at=existing.latest_session_ended_at if existing else None,
        )


@dataclass
class TaskResult:
    task_id: str
    name: str
    status: str
    outcome: str | None
    details: dict[str, Any]
    recorded_at: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "TaskResult":
        return cls(
            task_id=str(payload.get("task_id") or uuid4().hex),
            name=str(payload.get("name", "")),
            status=str(payload.get("status", "")),
            outcome=str(payload["outcome"]) if payload.get("outcome") is not None else None,
            details=dict(payload.get("details") or {}),
            recorded_at=str(payload.get("recorded_at", current_timestamp())),
        )

    @classmethod
    def create(
        cls,
        *,
        task_id: str | None,
        name: str,
        status: str,
        outcome: str | None,
        details: dict[str, Any] | None,
    ) -> "TaskResult":
        return cls(
            task_id=task_id or uuid4().hex,
            name=name,
            status=status,
            outcome=outcome,
            details=dict(details or {}),
            recorded_at=current_timestamp(),
        )


@dataclass
class SessionRecord:
    id: str
    project_id: str
    title: str
    status: str
    created_at: str
    started_at: str
    updated_at: str
    ended_at: str | None = None
    outcome: str | None = None
    task_results: list[TaskResult] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["task_results"] = [item.to_dict() for item in self.task_results]
        return payload

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "SessionRecord":
        timestamp = str(payload.get("started_at") or payload.get("created_at") or current_timestamp())
        return cls(
            id=str(payload["id"]),
            project_id=str(payload["project_id"]),
            title=str(payload.get("title", "")),
            status=str(payload.get("status", "running")),
            created_at=str(payload.get("created_at", timestamp)),
            started_at=timestamp,
            updated_at=str(payload.get("updated_at", timestamp)),
            ended_at=str(payload["ended_at"]) if payload.get("ended_at") is not None else None,
            outcome=str(payload["outcome"]) if payload.get("outcome") is not None else None,
            task_results=[TaskResult.from_dict(item) for item in payload.get("task_results", [])],
            metadata=dict(payload.get("metadata") or {}),
        )

    @classmethod
    def create(cls, project_id: str, title: str, metadata: dict[str, Any] | None = None) -> "SessionRecord":
        timestamp = current_timestamp()
        return cls(
            id=validate_storage_identifier(uuid4().hex, "session_id"),
            project_id=validate_storage_identifier(project_id, "project_id"),
            title=title,
            status="running",
            created_at=timestamp,
            started_at=timestamp,
            updated_at=timestamp,
            metadata=dict(metadata or {}),
        )

    def with_task_result(self, task_result: TaskResult) -> "SessionRecord":
        return SessionRecord(
            id=self.id,
            project_id=self.project_id,
            title=self.title,
            status=self.status,
            created_at=self.created_at,
            started_at=self.started_at,
            updated_at=current_timestamp(),
            ended_at=self.ended_at,
            outcome=self.outcome,
            task_results=[*self.task_results, task_result],
            metadata=dict(self.metadata),
        )

    def finished(self, *, status: str, outcome: str | None) -> "SessionRecord":
        timestamp = current_timestamp()
        return SessionRecord(
            id=self.id,
            project_id=self.project_id,
            title=self.title,
            status=status,
            created_at=self.created_at,
            started_at=self.started_at,
            updated_at=timestamp,
            ended_at=timestamp,
            outcome=outcome,
            task_results=list(self.task_results),
            metadata=dict(self.metadata),
        )


class ProjectRegistry:
    def __init__(self, base_dir: Path | None = None) -> None:
        self.base_dir = (base_dir or default_data_directory()).expanduser().resolve()
        self.runtime_dir = self.base_dir / "runtime"
        self.registry_path = self.runtime_dir / "projects.json"
        self._lock = threading.RLock()

    def _normalize_payload(self, raw_payload: Any) -> tuple[dict[str, Any], bool]:
        if raw_payload is None:
            return {"version": PROJECT_REGISTRY_VERSION, "projects": []}, False
        if isinstance(raw_payload, list):
            return {"version": PROJECT_REGISTRY_VERSION, "projects": raw_payload}, True
        if not isinstance(raw_payload, dict):
            raise ValueError(f"Unsupported project registry payload in {self.registry_path}")

        version = int(raw_payload.get("version", 1))
        projects = raw_payload.get("projects")
        if not isinstance(projects, list):
            raise ValueError(f"Project registry missing 'projects' list in {self.registry_path}")

        normalized = {"version": PROJECT_REGISTRY_VERSION, "projects": projects}
        return normalized, version != PROJECT_REGISTRY_VERSION

    def _load_registry_unlocked(self) -> dict[str, Any]:
        if not self.registry_path.exists():
            return {"version": PROJECT_REGISTRY_VERSION, "projects": []}

        raw_payload = json.loads(self.registry_path.read_text(encoding="utf-8"))
        payload, migrated = self._normalize_payload(raw_payload)
        if migrated:
            self._write_registry_unlocked(payload)
        return payload

    def _write_registry_unlocked(self, payload: dict[str, Any]) -> None:
        atomic_write_text(self.registry_path, json.dumps(payload, indent=2, sort_keys=True))

    def list_projects(self) -> list[RegisteredProject]:
        with self._lock:
            payload = self._load_registry_unlocked()
            records = [RegisteredProject.from_dict(item) for item in payload["projects"]]
        return sorted(records, key=lambda item: item.updated_at, reverse=True)

    def get_project(self, project_id: str) -> RegisteredProject | None:
        for project in self.list_projects():
            if project.id == project_id:
                return project
        return None

    def find_by_path(self, project_path: str) -> RegisteredProject | None:
        normalized_path = str(Path(project_path).expanduser().resolve())
        for project in self.list_projects():
            if str(Path(project.project_path).expanduser().resolve()) == normalized_path:
                return project
        return None

    def get_project_by_path(self, project_path: str) -> RegisteredProject | None:
        return self.find_by_path(project_path)

    def save_project(self, project: RegisteredProject) -> RegisteredProject:
        with self._lock:
            payload = self._load_registry_unlocked()
            records = [RegisteredProject.from_dict(item) for item in payload["projects"]]
            updated = [item for item in records if item.id != project.id]
            updated.append(project)
            payload["projects"] = [item.to_dict() for item in updated]
            self._write_registry_unlocked(payload)
        return project

    def _load_projects_unlocked(self) -> list[RegisteredProject]:
        payload = self._load_registry_unlocked()
        return [RegisteredProject.from_dict(item) for item in payload["projects"]]

    def _save_projects_unlocked(self, projects: list[RegisteredProject]) -> None:
        payload = {"version": PROJECT_REGISTRY_VERSION, "projects": [item.to_dict() for item in projects]}
        self._write_registry_unlocked(payload)

    def delete_project(self, project_id: str) -> None:
        with self._lock:
            records = self._load_projects_unlocked()
            self._save_projects_unlocked([item for item in records if item.id != project_id])

    def register_project(self, request: BootstrapRequest, result: CommandResult) -> RegisteredProject:
        existing = self.find_by_path(request.project_path)
        project = RegisteredProject.from_bootstrap(request, result, existing=existing)
        return self.save_project(project)

    def record_session_start(self, project_id: str, session: SessionRecord) -> RegisteredProject:
        with self._lock:
            records = self._load_projects_unlocked()
            project: RegisteredProject | None = None
            for item in records:
                if item.id == project_id:
                    project = item
                    break
            if project is None:
                raise KeyError(f"Unknown project id: {project_id}")
            project.session_count += 1
            project.updated_at = current_timestamp()
            project.latest_session_id = session.id
            project.latest_session_started_at = session.started_at
            project.latest_session_status = session.status
            project.latest_session_outcome = session.outcome
            project.latest_session_ended_at = session.ended_at
            self._save_projects_unlocked(records)
            return project

    def record_session_update(self, project_id: str, session: SessionRecord) -> RegisteredProject:
        with self._lock:
            records = self._load_projects_unlocked()
            project: RegisteredProject | None = None
            for item in records:
                if item.id == project_id:
                    project = item
                    break
            if project is None:
                raise KeyError(f"Unknown project id: {project_id}")
            if project.latest_session_id == session.id or project.latest_session_id is None:
                project.updated_at = current_timestamp()
                project.latest_session_id = session.id
                project.latest_session_started_at = session.started_at
                project.latest_session_status = session.status
                project.latest_session_outcome = session.outcome
                project.latest_session_ended_at = session.ended_at
                self._save_projects_unlocked(records)
            return project


class SessionRegistry:
    def __init__(self, base_dir: Path | None = None) -> None:
        self.base_dir = (base_dir or default_data_directory()).expanduser().resolve()
        self.runtime_dir = self.base_dir / "runtime"
        self.sessions_dir = self.runtime_dir / "sessions"
        self.legacy_path = self.runtime_dir / "sessions.json"
        self._lock = threading.RLock()
        self._migrate_legacy_sessions()

    def _session_file(self, project_id: str) -> Path:
        safe_project_id = validate_storage_identifier(project_id, "project_id")
        path = (self.sessions_dir / f"{safe_project_id}.ndjson").resolve()
        sessions_root = self.sessions_dir.resolve()
        try:
            path.relative_to(sessions_root)
        except ValueError as error:  # pragma: no cover - guarded by identifier validation
            raise ValueError("project_id resolves outside the sessions directory.") from error
        return path

    def _append_snapshot_unlocked(self, session: SessionRecord) -> None:
        validate_storage_identifier(session.id, "session_id")
        line = json.dumps(session.to_dict(), sort_keys=True) + "\n"
        append_text_line(self._session_file(session.project_id), line)

    def _load_project_sessions_unlocked(self, project_id: str) -> list[SessionRecord]:
        project_id = validate_storage_identifier(project_id, "project_id")
        path = self._session_file(project_id)
        if not path.exists():
            return []

        sessions: dict[str, SessionRecord] = {}
        with path.open("r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line:
                    continue
                payload = json.loads(line)
                session = SessionRecord.from_dict(payload)
                validate_storage_identifier(session.id, "session_id")
                validate_storage_identifier(session.project_id, "project_id")
                sessions[session.id] = session
        return sorted(sessions.values(), key=lambda item: item.started_at, reverse=True)

    def _migrate_legacy_sessions(self) -> None:
        with self._lock:
            if not self.legacy_path.exists():
                return

            self.sessions_dir.mkdir(parents=True, exist_ok=True)
            payload = json.loads(self.legacy_path.read_text(encoding="utf-8"))
            if not isinstance(payload, list):
                raise ValueError(f"Unsupported legacy sessions payload in {self.legacy_path}")

            for item in payload:
                session = SessionRecord.from_dict(item)
                if self.get_session(session.id, project_id=session.project_id) is None:
                    self._append_snapshot_unlocked(session)
            self.legacy_path.unlink()

    def list_sessions(self, project_id: str | None = None) -> list[SessionRecord]:
        with self._lock:
            if project_id is not None:
                return self._load_project_sessions_unlocked(validate_storage_identifier(project_id, "project_id"))

            sessions: list[SessionRecord] = []
            if not self.sessions_dir.exists():
                return []
            for path in self.sessions_dir.glob("*.ndjson"):
                sessions.extend(self._load_project_sessions_unlocked(path.stem))
            return sorted(sessions, key=lambda item: item.started_at, reverse=True)

    def get_session(self, session_id: str, *, project_id: str | None = None) -> SessionRecord | None:
        with self._lock:
            session_id = validate_storage_identifier(session_id, "session_id")
            candidate_projects: list[str]
            if project_id is not None:
                candidate_projects = [validate_storage_identifier(project_id, "project_id")]
            else:
                if not self.sessions_dir.exists():
                    return None
                candidate_projects = [path.stem for path in self.sessions_dir.glob("*.ndjson")]

            for candidate_project in candidate_projects:
                for session in self._load_project_sessions_unlocked(candidate_project):
                    if session.id == session_id:
                        return session
        return None

    def latest_session(self, project_id: str) -> SessionRecord | None:
        sessions = self.list_sessions(project_id=validate_storage_identifier(project_id, "project_id"))
        return sessions[0] if sessions else None

    def start_session(
        self,
        project_id: str,
        title: str,
        *,
        metadata: dict[str, Any] | None = None,
    ) -> SessionRecord:
        with self._lock:
            project_id = validate_storage_identifier(project_id, "project_id")
            session = SessionRecord.create(project_id=project_id, title=title, metadata=metadata)
            self._append_snapshot_unlocked(session)
            return session

    def record_task_result(
        self,
        session_id: str,
        *,
        name: str,
        status: str,
        outcome: str | None,
        details: dict[str, Any] | None = None,
        task_id: str | None = None,
        project_id: str | None = None,
    ) -> SessionRecord:
        with self._lock:
            session_id = validate_storage_identifier(session_id, "session_id")
            if project_id is not None:
                project_id = validate_storage_identifier(project_id, "project_id")
            session = self.get_session(session_id, project_id=project_id)
            if session is None:
                raise KeyError(f"Unknown session id: {session_id}")
            task_result = TaskResult.create(
                task_id=task_id,
                name=name,
                status=status,
                outcome=outcome,
                details=details,
            )
            updated_session = session.with_task_result(task_result)
            self._append_snapshot_unlocked(updated_session)
            return updated_session

    def end_session(
        self,
        session_id: str,
        *,
        outcome: str | None,
        status: str | None = None,
        project_id: str | None = None,
    ) -> SessionRecord:
        with self._lock:
            session_id = validate_storage_identifier(session_id, "session_id")
            if project_id is not None:
                project_id = validate_storage_identifier(project_id, "project_id")
            session = self.get_session(session_id, project_id=project_id)
            if session is None:
                raise KeyError(f"Unknown session id: {session_id}")
            final_status = status or ("completed" if outcome in {None, "success", "completed"} else "failed")
            updated_session = session.finished(status=final_status, outcome=outcome)
            self._append_snapshot_unlocked(updated_session)
            return updated_session
