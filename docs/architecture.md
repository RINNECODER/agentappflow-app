# AgentAppFlow App Architecture

## Summary

`agentappflow-app` is the primary product repo for AgentAppFlow. The product is Mac-first in UX, local-only in execution, Python-first for AI cognition, and Rust-enforced for privileged operations.

The app does not depend on a hosted backend. User projects keep their framework state in a visible `.agentappflow/` directory so the project contract is inspectable, portable, and discoverable by local AI agents.

The current runtime foundation is intentionally narrower than the long-term architecture: Swift keeps the UI and selection state, Python owns the runtime registry and session metadata, and Rust remains deferred for guarded execution.

## Runtime Boundaries

### Swift macOS app

Responsibilities:
- onboarding and project registration
- runtime-backed workspace selection and restoration
- session start entry points, settings, and approval controls
- session history, framework health views, and transient runtime error handling
- user-facing controls for self-improvement mode and memory visibility

The Swift app is the human control plane. It does not implement agent cognition or directly perform privileged repo mutations.

### Python core

Responsibilities:
- project bootstrap generation
- AI orchestration and tool routing
- memory ingestion, indexing orchestration, and retrieval
- task retrospectives and framework update proposals
- HyperAgent-inspired internal role coordination

The Python core is the AI brain. It owns the high-level workflow, but it must not bypass Rust for guarded writes or privileged command execution.

### Rust executor

Responsibilities:
- command execution policy
- filesystem mutation guardrails
- diff validation and audit records
- future sandboxed execution of sensitive operations

Rust is the trust boundary for risky local actions. It validates requests, executes or rejects them, and returns structured execution metadata.

## Inter-Process Communication

### Swift to Python

- transport: local Unix domain socket
- protocol: JSON-RPC
- purpose: app-driven commands such as runtime health checks, project registration, project listing, project reload, session start, approval changes, and retrospective generation

### Python to Rust

- transport: JSON over stdio per invocation
- purpose: request policy-checked execution, guarded file writes, command runs, and audit metadata

This split keeps the UI responsive, the AI runtime flexible, and the enforcement layer narrow and testable.

## Local-Only Service Commands

Implemented in the current runtime foundation:
- `health_check`
- `bootstrap_project`
- `register_project`
- `list_projects`
- `get_project`
- `start_session`

Implemented in the runtime core:
- `health_check`
- `bootstrap_project`
- `register_project`
- `list_projects`
- `get_project`
- `start_session`
- `record_task_result`
- `end_session`

Planned for later milestones:
- `generate_retrospective`
- `propose_framework_update`
- `apply_framework_update`
- `set_approval_mode`

These commands are local APIs, not network APIs.

## Runtime State Storage

Runtime-owned state is stored outside the repo under:
- `~/Library/Application Support/AgentAppFlow/runtime/projects.json`
- `~/Library/Application Support/AgentAppFlow/runtime/sessions/<project-id>.ndjson`

Tests and local tooling can override that location with `AGENTAPPFLOW_RUNTIME_HOME`.

The control center restores the selected project by persisting the runtime project identifier in user defaults and reloading that project through `get_project` on launch. Transient runtime failures should surface as runtime errors, not force the user back into onboarding.

## HyperAgent-Inspired Workflow

The Python core should coordinate four internal roles:
- Planner: turns a user task into an execution strategy
- Navigator: gathers repo context and project memory
- Editor: drafts framework or code changes
- Executor: asks the Rust layer to perform guarded actions

This borrows the role specialization pattern from HyperAgent while adapting it to a productized local workflow rather than benchmark-only task execution.

## Self-Improvement Policy

Each project exposes a configurable improvement mode:
- `observe`: collect retrospectives and lessons only
- `propose`: generate framework updates and require approval before activation
- `auto`: apply framework-only improvements automatically

Default mode is `propose`.

In `auto`, the system may update only framework-owned paths inside `.agentappflow/`, specifically rules, templates, and proposal state. It must not silently rewrite arbitrary user source files outside the normal coding workflow.

## Non-Goals For This Phase

- no backend services
- no cross-device sync
- no OS-agnostic app shell yet
- no attempt to make Rust the primary AI orchestration runtime

## Phase 2 Runtime Note

The current executable slice upgrades the bootstrap-only shell into a local runtime foundation:

- Swift launches and talks to the Python core over JSON-RPC on a Unix domain socket.
- The macOS app bundles its own `Python3.framework` and launches that embedded interpreter for runtime calls instead of relying on a user-installed `python3`.
- Python owns a small local registry for registered projects and session metadata under the user's Application Support directory.
- Onboarding bootstraps a repo and then registers it with the runtime instead of persisting a one-off Swift snapshot.
- The control center reads runtime-backed project and session state and restores the last selected project through the runtime.

Rust remains a deferred boundary for guarded execution and policy enforcement after the Swift to Python lifecycle and local project/session registry are proven end to end.
