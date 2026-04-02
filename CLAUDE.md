# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Source Control Workflow

- Base branch is `dev`. Never commit directly to `main`.
- If the current branch is `dev`, create a focused story branch before editing (e.g., `feat/us-001-runtime-onboarding`).
- Run `git status --short` before coding. Do not overwrite or stage unrelated user changes.
- Do not push unless the selected story explicitly requires a remote action.

## Build & QA Gates

**If Python files under `python/` change:**
```bash
python3 -m pytest python/tests
```

**If Swift files, `project.yml`, or `.pbxproj` change:**
```bash
xcodegen generate
xcodebuild -project AgentAppFlow.xcodeproj -scheme AgentAppFlow -destination 'platform=macOS' test
```

- Never hand-edit `AgentAppFlow.xcodeproj/project.pbxproj` — always regenerate via `xcodegen generate` after modifying `project.yml`.
- If docs or architecture notes change, verify referenced commands, file paths, and runtime boundaries still match the code.

**Run a single Swift test suite:**
```bash
xcodebuild -project AgentAppFlow.xcodeproj -scheme AgentAppFlow -destination 'platform=macOS' -only-testing:AgentAppFlowTests/PythonRuntimeLocatorTests test
```

**Run a specific Python test file:**
```bash
python3 -m pytest python/tests/test_bootstrap.py
```

## Architecture

AgentAppFlow is a **local-first macOS control center** for project-aware AI development workflows. There is no backend — all execution runs locally. The system has three layers:

### 1. Swift macOS App (UI Control Plane)
- Owns onboarding, project registration, approval controls, session history, and framework health views.
- Does **not** implement agent cognition or direct repository mutations.
- Communicates with the Python runtime over a **Unix domain socket** using JSON-RPC 2.0.
- Key services: `AgentRuntimeService` (process lifecycle + JSON-RPC client), `AppRuntimeStore` (ObservableObject state), `PythonRuntimeLocator` (finds `Python3.framework`), `BootstrapCLIService` (orchestrates project init).
- `Python3.framework` is embedded in the app bundle via `scripts/embed_python_runtime.sh` (a post-build Xcode phase). Override the framework path with `AGENTAPPFLOW_PYTHON_FRAMEWORK_PATH`.

### 2. Python Core (AI Orchestration)
- Entry point: `python/agentappflow_bootstrap.py` with `bootstrap_project` and `serve` subcommands.
- `agentappflow_core/runtime.py` — JSON-RPC dispatcher (`AgentAppFlowRuntime`); socket server via `run_runtime_server()`. Runtime version: 0.2.0.
- `agentappflow_core/bootstrap.py` — Creates and validates the `.agentappflow/` directory structure in a project.
- `agentappflow_core/storage.py` — `ProjectRegistry` and `SessionRegistry` backed by local Application Support directory.

### 3. Rust Executor (Deferred — Phase 2+)
- Will own command execution policy, filesystem mutation guardrails, diff validation, and audit logging.
- Will communicate with Python via JSON over stdio per invocation.

### IPC
- Swift ↔ Python: Unix domain socket, JSON-RPC 2.0.
- Python ↔ Rust: JSON via stdio (not yet implemented).

### Local Project Framework (`.agentappflow/`)
Each bootstrapped project gets a `.agentappflow/` directory containing `project.yaml`, `rules/`, `templates/`, `sessions/`, `retros/`, `proposals/`, `cache/`, and agent adapter files (`AGENTS.md`, `CLAUDE.md`). This state is local and git-traceable. See `docs/project-framework.md` for the full contract.

## Release

Releases are built by GitHub Actions (`release-dmg.yml`) on tag push matching `v*`:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds a Release DMG and publishes it to GitHub Releases. Current builds are unsigned (Gatekeeper warning until code signing/notarization is added).

## Xcode Project Configuration

The Xcode project is generated from `project.yml` using XcodeGen:
- Swift 5.0, macOS 15.0 deployment target
- Bundle ID: `com.rinnecoder.agentappflow`
- Targets: `AgentAppFlow` (app) + `AgentAppFlowTests` (unit tests)
