# agentappflow-app

Primary product repo for AgentAppFlow.

AgentAppFlow App is a Mac-first local control center for project-aware AI development workflows. It owns the product UX, the local runtime architecture, and the project framework contract that AI coding agents follow inside user repositories.

## Product Direction
- macOS app in Swift for onboarding, project registration, runtime-backed workspace selection, approval controls, session history, and framework health.
- Python core for AI orchestration, memory ingestion and retrieval, retrospectives, and self-improvement proposals.
- Rust executor for guarded command execution, filesystem policy enforcement, diff validation, and audit logging.
- No backend: all state and automation run locally on the user's machine.

## Architecture
- Swift talks to the Python core over local JSON-RPC on a Unix domain socket.
- The runtime command surface implemented in this milestone is `health_check`, `register_project`, `list_projects`, `get_project`, and `start_session`, with `bootstrap_project` still available for onboarding.
- Runtime-backed project and session state live under `~/Library/Application Support/AgentAppFlow/runtime/` unless `AGENTAPPFLOW_RUNTIME_HOME` is set for tests or local overrides.
- The control center restores the selected project by persisting its runtime project ID and reloading it through the local runtime on launch.
- Python delegates privileged execution and guarded writes to Rust over JSON via stdio.
- Each managed user project gets a `.agentappflow/` directory that stores project config, rules, templates, memory summaries, and framework proposals.
- Self-improvement is project-specific and configurable in the app with `observe`, `propose`, and `auto` modes.

## Docs
- [Architecture](./docs/architecture.md)
- [Project Framework Contract](./docs/project-framework.md)

## Local Development
- Work from the repo root and branch from `dev`.
- Run `xcodegen generate` whenever `project.yml` changes; commit the regenerated `AgentAppFlow.xcodeproj/project.pbxproj` in the same change.
- Run `xcodebuild -project AgentAppFlow.xcodeproj -scheme AgentAppFlow -destination 'platform=macOS' test` when Swift sources or Xcode project files change.
- Run `python3 -m pytest python/tests` when runtime files under `python/` change.
- Update docs whenever onboarding behavior, runtime boundaries, or contributor workflow change.

## Automatic Releases
- Pushing a tag that matches `v*` triggers the GitHub Actions workflow at `.github/workflows/release-dmg.yml`.
- The workflow builds the `Release` macOS app, packages `AgentAppFlow.app` into `AgentAppFlow-<tag>.dmg`, and publishes it to the matching GitHub Release.
- Each release also uploads `SHA256SUMS.txt` so downloads can be verified.

Release flow:
```bash
git tag v0.1.0
git push origin v0.1.0
```

Download flow:
- Open the latest release on GitHub and download the `.dmg` asset:
  `https://github.com/RINNECODER/agentappflow-app/releases/latest`
- Because the current pipeline produces an unsigned build, macOS may show a Gatekeeper warning until code signing and notarization are added.

## Role In The Ecosystem
This repository is the primary entrypoint for the AgentAppFlow product. Supporting repos keep shared docs, plugins, skills, and CLI tooling separated for now, but this repo defines the product architecture and the user-facing direction.

## Branching
- `main`: stable baseline
- `dev`: active development

## License
MIT (see [LICENSE](./LICENSE)).
