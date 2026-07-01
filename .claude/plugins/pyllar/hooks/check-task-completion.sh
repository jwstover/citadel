#!/bin/bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TASK_FILE="$PLUGIN_ROOT/memory/current-task.md"

if [ ! -f "$TASK_FILE" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

task_id=$(grep "^task_id:" "$TASK_FILE" | sed 's/^task_id: //' | tr -d '[:space:]')
human_id=$(grep "^human_id:" "$TASK_FILE" | sed 's/^human_id: //' | tr -d '[:space:]')
title=$(grep "^title:" "$TASK_FILE" | sed 's/^title: //')

if [ -z "$task_id" ] || [ -z "$human_id" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

cat <<ENDJSON
{
  "decision": "block",
  "reason": "Active Pyllar task: $human_id",
  "systemMessage": "Before ending this session, handle the active Pyllar task.\n\nActive task: **$human_id** —$title\nTask UUID: $task_id\n\nEvaluate whether the work on this task is complete:\n- Were the acceptance criteria met?\n- Did tests pass (if applicable)?\n- Did the user confirm the work is done?\n\nThen take ONE of these actions:\n\n1. **Work is complete**: Update the task to \"In Review\" using \`mcp__pyllar__update_task\` with the In Review state ID, then delete \`$TASK_FILE\`.\n2. **Work is incomplete**: Leave the task in \"In Progress\". Delete \`$TASK_FILE\` and briefly tell the user what remains.\n3. **Work is blocked**: Leave the task in \"In Progress\". Delete \`$TASK_FILE\` and note the blocker.\n\nYou MUST delete \`$TASK_FILE\` regardless of which action you take."
}
ENDJSON
