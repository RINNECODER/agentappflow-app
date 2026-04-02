# Ralph defaults for the runtime foundation loop in `agentappflow-app`.

PRD_PATH=".agents/tasks/prd-runtime-foundation.json"
PROGRESS_PATH=".ralph/progress.md"
GUARDRAILS_PATH=".ralph/guardrails.md"
ERRORS_LOG_PATH=".ralph/errors.log"
ACTIVITY_LOG_PATH=".ralph/activity.log"
TMP_DIR=".ralph/.tmp"
RUNS_DIR=".ralph/runs"
GUARDRAILS_REF=".agents/ralph/references/GUARDRAILS.md"
CONTEXT_REF=".agents/ralph/references/CONTEXT_ENGINEERING.md"
ACTIVITY_CMD=".agents/ralph/log-activity.sh"
AGENTS_PATH="AGENTS.md"
PROMPT_BUILD=".agents/ralph/PROMPT_build.md"

AGENT_CMD="/Applications/Codex.app/Contents/Resources/codex exec --yolo --skip-git-repo-check -"
PRD_AGENT_CMD="/Applications/Codex.app/Contents/Resources/codex --yolo --skip-git-repo-check {prompt}"

NO_COMMIT=false
MAX_ITERATIONS=8
STALE_SECONDS=1800
