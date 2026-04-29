# AgentAppFlow Ralph Operating Guide

## Scope
- Run Ralph from the `agentappflow-app` repo root only.
- Treat this repo as the source of truth for the macOS control center, the local runtime contract, and the `.agentappflow/` project framework.

## Source Control Workflow
- Base branch is `dev`. Never commit directly to `main`.
- If the current branch is `dev`, create a focused story branch before editing, for example `codex/us-001-runtime-onboarding`.
- Inspect `git status --short` before coding. Do not overwrite or stage unrelated user changes.
- Keep each Ralph story to one focused commit plus Ralph state updates.
- Do not push unless the selected story explicitly requires a remote action.

## Skill And Plugin Routing
- Use the RPI workflow for any multi-file, risky, or behavior-changing story:
  `rpi-research` -> `rpi-planning` -> `rpi-implementation`.
- For SwiftUI view work, prefer:
  - `build-ios-apps:swiftui-ui-patterns` for new UI or layout changes
  - `build-ios-apps:swiftui-view-refactor` for large view cleanup or decomposition
  - `build-ios-apps:swiftui-performance-audit` when a story risks update churn or rendering regressions
- Use GitHub plugin skills only for GitHub-specific stories such as PR review comments, CI failures, or publishing changes.
- Use Vercel or Build Web Apps skills only when a story explicitly touches web, docs-site, or deployment surfaces.
- Do not load browser-only skills for the macOS app unless the selected story is actually about a web surface in this repo.

## Build And QA Gates
- If Python files under `python/` change, run:
  `python3 -m pytest python/tests`
- If Swift files, `project.yml`, or `AgentAppFlow.xcodeproj/project.pbxproj` change, run:
  `xcodegen generate`
  `xcodebuild -project AgentAppFlow.xcodeproj -scheme AgentAppFlow -destination 'platform=macOS' test`
- If `project.yml` changes, regenerate `AgentAppFlow.xcodeproj/project.pbxproj` with `xcodegen generate`. Do not hand-edit the project file to keep it in sync.
- If docs or architecture notes change, verify the referenced commands, file paths, and runtime boundaries still match the code.

## Working Norms
- Update tests when behavior changes.
- Update docs when product flow, runtime boundaries, or developer workflow changes.
- Never commit secrets, generated noise, or unrelated formatting churn.
- If pre-existing dirty files make a clean story commit impossible, stop and record the blocker instead of mixing scopes.
