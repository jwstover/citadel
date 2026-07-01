---
description: Plan and create a new task with guided requirements clarification
argument-hint: <task description>
---

# Task Planning

You are helping the user plan and create a single task. Keep this lightweight — ask the right questions, draft a clear task, and create it after confirmation.

## Task Request

$ARGUMENTS

---

## Phase 1: Setup

Gather the information needed to create tasks by running these in parallel:

1. **Get task states** using `mcp__pyllar__list_task_states` to retrieve available states and their IDs. You'll need the "Backlog" state ID for new tasks.

2. **Get workspace** using `mcp__pyllar__get_current_workspace` to retrieve the workspace_id.

Store these values for use in Phase 4.

## Phase 2: Clarify

Before creating anything, make sure you understand the task. Ask 2-4 focused questions covering:

- **Scope**: What exactly should this accomplish? What's out of scope?
- **Acceptance criteria**: How will we know it's done?
- **Priority**: Is this urgent, high, medium, or low?
- **Context**: Is this related to or blocked by any existing work?

<ask_questions>
Use AskUserQuestion to gather this information efficiently. Adapt your questions based on the task description — skip what's already clear from the request, focus on what's ambiguous.

If the request is already detailed and unambiguous, you may skip directly to Phase 3.
</ask_questions>

## Phase 3: Draft

Based on the request and any clarifications, draft the task for user review:

```
## Proposed Task

**Title**: [concise, action-oriented title]
**Priority**: [low | medium | high | urgent]

**Description**:
## Objective
[One sentence: what this task accomplishes]

## Requirements
- [ ] Requirement 1
- [ ] Requirement 2

## Acceptance Criteria
- [Verifiable criterion 1]
- [Verifiable criterion 2]
```

Adapt the description template as needed — skip sections that aren't relevant, add implementation guidance for technical tasks.

<stop_for_confirmation>
STOP HERE. Present the draft and ask:

"Here's the task I'd like to create. Any changes before I submit it?"

Do NOT proceed to Phase 4 until the user approves or says to go ahead.
</stop_for_confirmation>

## Phase 4: Create

After user approval, create the task using `mcp__pyllar__create_task` with:
- `title`: The approved title
- `description`: The full markdown description
- `workspace_id`: From Phase 1
- `task_state_id`: The "Backlog" state ID from Phase 1
- `priority`: As agreed with user

After creation, confirm with the task's human_id:

"Created **[human_id]** — [title]"
