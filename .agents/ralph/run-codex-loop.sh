#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PRD_PATH="${PRD_PATH:-.agents/tasks/prd-runtime-foundation.json}"
ITERATIONS="${RALPH_ITERATIONS:-8}"

if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
  ITERATIONS="$1"
  shift
fi

ALLOW_DIRTY="false"
for arg in "$@"; do
  if [[ "$arg" == "--no-commit" ]]; then
    ALLOW_DIRTY="true"
    break
  fi
done

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" == "main" ]]; then
  echo "Refusing to run Ralph on main. Switch to dev or a story branch first."
  exit 1
fi

if [[ -n "$(git status --porcelain)" && "$ALLOW_DIRTY" != "true" ]]; then
  echo "Worktree is dirty. Commit or stash existing changes first, or rerun with --no-commit."
  exit 1
fi

exec ralph build "$ITERATIONS" --agent=codex --prd "$PRD_PATH" "$@"
