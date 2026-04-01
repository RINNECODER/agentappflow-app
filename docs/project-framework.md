# Project Framework Contract

## Summary

Every managed user repository gets a `.agentappflow/` directory at the repo root. This directory is the project-local contract between AgentAppFlow and AI coding agents such as Codex and Claude Code.

The goal is to keep canonical project memory and framework rules visible inside the repo while allowing derived indexes and caches to remain local implementation details.

## Directory Layout

```text
.agentappflow/
  project.yaml
  rules/
  templates/
  sessions/
  retros/
  proposals/
  cache/
```

### Required paths

- `project.yaml`: project identity, stack, goals, enabled agent tools, and policy settings
- `rules/`: generated working rules and project guardrails
- `templates/`: task, review, onboarding, and retrospective templates
- `sessions/`: human-readable session summaries and transcripts
- `retros/`: post-task Q&A, outcomes, and lessons learned
- `proposals/`: pending or accepted framework changes
- `cache/`: derived local indexes such as SQLite, embeddings, or search artifacts

## `project.yaml` Contract

Initial required fields:

```yaml
project_type: ios_app
platforms:
  - macos
  - ios
tech_stack:
  ui: swift
  orchestration: python
  execution: rust
agent_tools:
  - codex
  - claude_code
approval_mode: propose
memory_mode: local_repo
improvement_mode: propose
```

Core fields:
- `project_type`
- `platforms`
- `tech_stack`
- `agent_tools`
- `approval_mode`
- `memory_mode`
- `improvement_mode`

## Canonical vs Derived State

Canonical state should stay human-readable and live in version-controlled repo paths when appropriate:
- `project.yaml`
- rules
- templates
- session summaries
- retrospectives
- proposals

Derived state belongs in `.agentappflow/cache/` and should usually be gitignored:
- SQLite indexes
- embeddings
- retrieval caches
- temporary execution metadata

## Agent Adapter Files

The framework should generate thin root-level adapter files:
- `AGENTS.md` for Codex-compatible tools
- `CLAUDE.md` for Claude Code and similar agent runtimes

These files should point agents into `.agentappflow/` rather than duplicating all framework content at repo root.

## Approval Modes

- `observe`: do not activate framework updates
- `propose`: create a proposal and wait for user approval
- `auto`: activate framework-only changes automatically

`auto` must be constrained to framework-owned paths and may not silently modify unrelated user source code.

## Retrospective Output

After each task, the framework should capture:
- what succeeded
- what failed or created friction
- what should change in the framework
- confidence level
- evidence or examples from the finished task

That output becomes the basis for future framework proposals and project specialization.
