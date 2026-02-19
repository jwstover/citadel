---
description: Start working on a Pyllar task. Automatically sets task to "In Progress" and loads context.
argument-hint: <task-id>
---

# Work on Task: $ARGUMENTS

You are starting work on a Pyllar task. Fetch the task, transition it to "In Progress", and load all relevant context.

---

## Phase 1: Fetch & Validate

Run these in parallel:

1. **Fetch the task** using `mcp__pyllar__list_tasks` with filter:
   ```json
   {"human_id": {"eq": "$ARGUMENTS"}}
   ```

2. **Get task states** using `mcp__pyllar__list_task_states` to retrieve available states and their IDs. You'll need the "In Progress" state ID.

3. **Get workspace** using `mcp__pyllar__get_current_workspace` for workspace context.

**Validate the task**:
- If the task is not found, inform the user and stop.
- If the task's state has `is_complete: true`, warn the user: "This task is already marked complete. Do you want to reopen it?"
- If the task is already "In Progress", note it and continue to Phase 2 without updating state.

## Phase 2: Set In Progress

If the task is not already "In Progress":

**Update the task state** using `mcp__pyllar__update_task` with the task's UUID and the "In Progress" `task_state_id`.

Confirm: "**$ARGUMENTS** is now In Progress."

## Phase 3: Track Session

Write the current task to `${CLAUDE_PLUGIN_ROOT}/memory/current-task.md` so that hooks and other commands can detect which task is active:

```markdown
---
task_id: <task_uuid>
human_id: $ARGUMENTS
title: <task_title>
started_at: <current ISO 8601 timestamp>
---
```

This file is overwritten each time `/pyllar:work-on` is invoked.

## Phase 4: Load Context

Gather full context by running these in parallel:

1. **Check for sub-tasks** using `mcp__pyllar__list_tasks` with filter:
   ```json
   {"parent_task_id": {"eq": "<task_uuid>"}}
   ```

2. **Check for parent task** — if the task has a `parent_task_id`, fetch the parent using `mcp__pyllar__list_tasks` with filter:
   ```json
   {"id": {"eq": "<parent_task_uuid>"}}
   ```

3. **Check for sibling tasks** — if this is a subtask, also fetch other subtasks of the parent to understand broader context:
   ```json
   {"parent_task_id": {"eq": "<parent_task_uuid>"}}
   ```

## Phase 5: Present Context

Display a summary of the task:

```
## [human_id]: [title]
**Priority**: [priority]
**State**: In Progress

### Description
[task description]

### Sub-tasks
- [x] [completed subtask title] ([human_id])
- [ ] [pending subtask title] ([human_id])
(or "No sub-tasks")

### Parent Task
[parent human_id]: [parent title] — [parent state]
(or "This is a top-level task")
```

Then suggest next steps:

1. **Feature branch** (if not already on one):
   ```
   git checkout -b feat/$ARGUMENTS-<short-description>
   ```

2. **Read project conventions**: Review `CLAUDE.md` and `AGENTS.md` to understand project patterns.

3. **Break down the work**: Analyze the task description and create a concrete implementation plan.

---

Begin by fetching task **$ARGUMENTS** now.
