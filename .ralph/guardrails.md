# Ralph Guardrails

## Signs

### Protect pre-existing worktree changes
- Before coding, inspect `git status --short`.
- Do not overwrite or stage unrelated dirty files.
- If a clean story commit is impossible, stop and record the blocker.

### Keep source control focused
- Never commit on `main`.
- If the current branch is `dev`, create a story branch before editing.
- Stage only story-related files plus Ralph state files updated by the run.

### Keep Xcode generation deterministic
- If `project.yml` changes, run `xcodegen generate`.
- Do not hand-edit `AgentAppFlow.xcodeproj/project.pbxproj` unless the generated file is being synchronized from `project.yml`.

### Match QA to the surface changed
- Run `python3 -m pytest python/tests` for Python runtime changes.
- Run `xcodebuild -project AgentAppFlow.xcodeproj -scheme AgentAppFlow -destination 'platform=macOS' test` for Swift or Xcode project changes.
- Update docs when runtime boundaries or contributor workflow change.
