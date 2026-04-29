# PRD Overview: AgentAppFlow Runtime Foundation

- File: .agents/tasks/prd-runtime-foundation.json
- Stories: 3 total (3 open, 0 in_progress, 0 done)

## Quality Gates
- Inspect git status before editing and do not mix unrelated dirty files into a story commit
- python3 -m pytest python/tests when Python runtime files change
- xcodegen generate when Swift sources, project.yml, or the Xcode project need sync
- xcodebuild -project AgentAppFlow.xcodeproj -scheme AgentAppFlow -destination 'platform=macOS' test when Swift or Xcode project files change
- Update docs when runtime architecture or developer workflow changes

## Stories
- [open] US-001: Complete runtime-backed onboarding handoff
- [open] US-002: Harden embedded Python runtime execution (depends on: US-001)
- [open] US-003: Align docs and project generation with the runtime foundation (depends on: US-001, US-002)
