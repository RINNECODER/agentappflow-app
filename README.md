# agentappflow-app

Primary product repo for AgentAppFlow.

AgentAppFlow App is a Mac-first local control center for project-aware AI development workflows. It owns the product UX, the local runtime architecture, and the project framework contract that AI coding agents follow inside user repositories.

## Product Direction
- macOS app in Swift for onboarding, project registration, approval controls, session history, and framework health.
- Python core for AI orchestration, memory ingestion and retrieval, retrospectives, and self-improvement proposals.
- Rust executor for guarded command execution, filesystem policy enforcement, diff validation, and audit logging.
- No backend: all state and automation run locally on the user's machine.

## Architecture
- Swift talks to the Python core over local JSON-RPC on a Unix domain socket.
- Python delegates privileged execution and guarded writes to Rust over JSON via stdio.
- Each managed user project gets a `.agentappflow/` directory that stores project config, rules, templates, memory summaries, and framework proposals.
- Self-improvement is project-specific and configurable in the app with `observe`, `propose`, and `auto` modes.

## Docs
- [Architecture](./docs/architecture.md)
- [Project Framework Contract](./docs/project-framework.md)

## Role In The Ecosystem
This repository is the primary entrypoint for the AgentAppFlow product. Supporting repos keep shared docs, plugins, skills, and CLI tooling separated for now, but this repo defines the product architecture and the user-facing direction.

## Branching
- `main`: stable baseline
- `dev`: active development

## License
MIT (see [LICENSE](./LICENSE)).
