# Contributing to agentappflow-app

Thanks for your interest in contributing.

## Workflow
- Create a branch from `dev` for your changes.
- Keep pull requests focused and small.
- Add or update docs/tests when behavior changes.
- Treat this repo as the source of truth for product UX direction, local runtime boundaries, and the `.agentappflow/` project contract.
- Run from the repo root so bundled runtime paths and generated project paths stay consistent.

## Verification
- Run `xcodegen generate` if `project.yml` changes. Commit the regenerated `AgentAppFlow.xcodeproj/project.pbxproj` in the same change.
- Run `xcodebuild -project AgentAppFlow.xcodeproj -scheme AgentAppFlow -destination 'platform=macOS' test` when Swift sources or Xcode project files change.
- Run `python3 -m pytest python/tests` when runtime files under `python/` change.
- Update documentation when onboarding, runtime boundaries, or contributor workflow change.

## Development Branches
- `main`: stable baseline
- `dev`: integration branch

## Pull Request Checklist
- [ ] Code builds locally
- [ ] Relevant tests added/updated
- [ ] Documentation updated
- [ ] No secrets committed
