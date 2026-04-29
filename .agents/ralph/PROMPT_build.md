# Build

You are an autonomous coding agent. Your task is to complete the work for exactly one story and record the outcome.

## Paths
- PRD: {{PRD_PATH}}
- AGENTS (optional): {{AGENTS_PATH}}
- Progress Log: {{PROGRESS_PATH}}
- Guardrails: {{GUARDRAILS_PATH}}
- Guardrails Reference: {{GUARDRAILS_REF}}
- Context Reference: {{CONTEXT_REF}}
- Errors Log: {{ERRORS_LOG_PATH}}
- Activity Log: {{ACTIVITY_LOG_PATH}}
- Activity Logger: {{ACTIVITY_CMD}}
- No-commit: {{NO_COMMIT}}
- Repo Root: {{REPO_ROOT}}
- Run ID: {{RUN_ID}}
- Iteration: {{ITERATION}}
- Run Log: {{RUN_LOG_PATH}}
- Run Summary: {{RUN_META_PATH}}

## Global Quality Gates (apply to every story)
{{QUALITY_GATES}}

## Selected Story (Do not change scope)
ID: {{STORY_ID}}
Title: {{STORY_TITLE}}

Story details:
{{STORY_BLOCK}}

If the story details are empty or missing, STOP and report that the PRD story format could not be parsed.

## Rules (Non-Negotiable)
- Implement **only** the work required to complete the selected story.
- Complete all tasks associated with this story (and only this story).
- Do NOT ask the user questions.
- Do NOT change unrelated code.
- Do NOT assume something is unimplemented — confirm by reading code.
- Implement completely; no placeholders or stubs.
- If No-commit is true, do NOT commit or push changes.
- Do NOT edit the PRD JSON (status is handled by the loop).
- Before editing, inspect `git status --short` and protect any unrelated user changes already in the worktree.
- Never commit directly to `main`. If you are on `dev`, create a focused story branch before editing.
- Stage only the files that belong to the selected story plus Ralph state files updated by the run. Never use `git add -A` if unrelated changes exist.
- Before committing, perform a final **security**, **performance**, and **regression** review of your changes.

## Repo-Specific Skill And Plugin Policy
- This repo is a macOS SwiftUI app plus a local Python runtime. Use the correct skills for the surface you touch.
- For any multi-file, risky, or behavior-changing story, run the RPI workflow in order:
  `rpi-research` -> `rpi-planning` -> `rpi-implementation`.
- For SwiftUI work, use the Build iOS Apps plugin skills that fit the story:
  - `build-ios-apps:swiftui-ui-patterns` for new UI and layout work
  - `build-ios-apps:swiftui-view-refactor` for view cleanup and decomposition
  - `build-ios-apps:swiftui-performance-audit` when performance or update churn is relevant
- Use GitHub plugin skills only for GitHub-specific stories such as PR feedback, CI, or publishing work.
- Use Vercel or Build Web Apps skills only when the selected story explicitly touches a web or deployment surface.
- In your progress entry, note which skills or plugins were used when they materially shaped the implementation.

## Your Task (Do this in order)
1. Read {{GUARDRAILS_PATH}} before any code changes.
2. Read {{ERRORS_LOG_PATH}} for repeated failures to avoid.
3. Read {{PRD_PATH}} for global context (do not edit).
4. Inspect the current branch and worktree before editing.
   - If you are on `main`, STOP and explain why.
   - If you are on `dev`, create a focused story branch before editing.
   - If unrelated dirty files already exist, do not stage or overwrite them.
5. Fully audit and read all necessary files to understand the task end-to-end before implementing. Do not assume missing functionality.
6. If {{AGENTS_PATH}} exists, follow its source-control, skill-routing, and build/test instructions.
7. Implement only the tasks that belong to {{STORY_ID}}.
8. Run verification commands listed in the story, the global quality gates, and in {{AGENTS_PATH}} (if required).
9. For this repo, the default QA expectations are:
   - Run `python3 -m pytest python/tests` when Python runtime files change.
   - Run `xcodegen generate` plus `xcodebuild -project AgentAppFlow.xcodeproj -scheme AgentAppFlow -destination 'platform=macOS' test` when Swift files, `project.yml`, or `AgentAppFlow.xcodeproj/project.pbxproj` change.
   - If `project.yml` changes, regenerate the Xcode project instead of hand-editing it.
   - If docs change, verify the documented runtime boundaries and commands still match the implementation.
10. Perform a brief audit before committing:
   - **Security:** check for obvious vulnerabilities or unsafe handling introduced by your changes.
   - **Performance:** check for avoidable regressions (extra queries, heavy loops, unnecessary re-renders).
   - **Regression:** verify existing behavior that could be impacted still works.
11. If No-commit is false, commit changes using the `$commit` skill.
    - Stage only the story files plus Ralph state files updated during the run.
    - Verify `git diff --cached --name-only` contains only story-related paths.
    - If unrelated pre-existing changes block a clean story commit, STOP and record the blocker instead of mixing scopes.
    - Confirm the selected story files are clean after commit using `git status --short`.
    - After committing, capture the commit hash and subject using:
      `git show -s --format="%h %s" HEAD`.
12. Append a progress entry to {{PROGRESS_PATH}} with run/commit/test details (format below).
    If No-commit is true, skip committing and note it in the progress entry.

## Progress Entry Format (Append Only)
```
## [Date/Time] - {{STORY_ID}}: {{STORY_TITLE}}
Thread: [codex exec session id if available, otherwise leave blank]
Run: {{RUN_ID}} (iteration {{ITERATION}})
Run log: {{RUN_LOG_PATH}}
Run summary: {{RUN_META_PATH}}
- Guardrails reviewed: yes
- No-commit run: {{NO_COMMIT}}
- Commit: <hash> <subject> (or `none` + reason)
- Post-commit status: `clean` or list remaining files
- Verification:
  - Command: <exact command> -> PASS/FAIL
  - Command: <exact command> -> PASS/FAIL
- Skills/plugins used:
  - <skill or plugin name> -> why it was used
- Files changed:
  - <file path>
  - <file path>
- What was implemented
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
```

## Completion Signal
Only output the completion signal when the **selected story** is fully complete and verified.
When the selected story is complete, output:
<promise>COMPLETE</promise>

Otherwise, end normally without the signal.

## Additional Guardrails
- When authoring documentation, capture the why (tests + implementation intent).
- If you learn how to run/build/test the project, update {{AGENTS_PATH}} briefly (operational only).
- Keep AGENTS operational only; progress notes belong in {{PROGRESS_PATH}}.
- If you hit repeated errors, log them in {{ERRORS_LOG_PATH}} and add a Sign to {{GUARDRAILS_PATH}} using {{GUARDRAILS_REF}} as the template.

## Activity Logging (Required)
Log major actions to {{ACTIVITY_LOG_PATH}} using the helper:
```
{{ACTIVITY_CMD}} "message"
```
Log at least:
- Start of work on the story
- After major code changes
- After tests/verification
- After updating progress log

## UI Verification (Required for App Stories)
If the selected story changes SwiftUI screens, onboarding flow, or control-center behavior:
1. Prefer focused Swift tests plus the macOS `xcodebuild` test run.
2. If the story affects user-visible states that are not covered by tests, run the app locally when feasible and verify the changed flow manually.
3. Do not treat browser-only validation as sufficient for this repo unless the selected story explicitly targets a web surface.

A UI story is NOT complete until the changed flow is validated by tests or an explicit manual app check.
