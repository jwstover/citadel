---
name: breakdown
description: Break down a feature or epic into actionable subtasks. Use when planning new features, analyzing complex work, or when user says "break this down" or "create subtasks for".
argument-hint: <feature description>
---

# Task Breakdown Skill

You are breaking down a feature request into actionable subtasks with dependency detection. Your goal is to transform a natural language description into a hierarchical task structure in Pyllar.

## Feature Request

$ARGUMENTS

---

## Phase 1: Setup

First, gather the information needed to create tasks.

1. **Get task states** using `mcp__pyllar__list_task_states` to retrieve available states and their IDs. You'll need the "Backlog" state ID for new tasks.

2. **Get workspace** using `mcp__pyllar__get_current_workspace` to retrieve the workspace_id for task creation.

Store these values for use in Phase 5.

## Phase 2: Analyze the Feature

Analyze the feature description to identify:

1. **Main deliverable**: What is the core outcome? This becomes the parent task title.

2. **Logical subtasks**: Break the work into discrete implementation steps. Guidelines:
   - Prefer 3-7 subtasks (not too granular, not too coarse)
   - Each subtask should be completable in one focused work session
   - Consider the natural phases: research, data layer, business logic, UI, testing

3. **Technical dependencies**: Identify which tasks must complete before others can start:
   - Database/schema changes before API work
   - API work before UI implementation
   - Core functionality before edge cases
   - Setup/configuration before feature work

4. **Priority mapping**: Assign priorities based on dependencies and impact:
   - `urgent`: Blocking critical path
   - `high`: Foundational work or on critical path
   - `medium`: Standard implementation work
   - `low`: Nice-to-have refinements

## Phase 3: Clarify Requirements

<ask_questions>
If the feature description is ambiguous or missing key details, STOP and ask clarifying questions. Consider:

- What is the expected user experience?
- Are there specific technical constraints or preferences?
- What is NOT in scope for this feature?
- Are there related existing features to maintain consistency with?

Do not proceed until you have sufficient clarity.
</ask_questions>

## Phase 4: Present the Breakdown

Present your proposed task structure for user approval using this format:

```
## Parent Task
**Title**: [Feature title]
**Priority**: [suggested priority]

## Subtasks

1. **[Subtask title]** (Priority: [priority])
   - [Brief description]
   - Dependencies: [none | list of subtask numbers]

2. **[Subtask title]** (Priority: [priority])
   - [Brief description]
   - Dependencies: [none | subtask 1]

[...continue for all subtasks]
```

<stop_for_confirmation>
STOP HERE. Ask the user:

"This is my proposed task breakdown. Before I create these tasks in Pyllar:
- Does this structure make sense for your needs?
- Should any subtasks be added, removed, or reordered?
- Are the priorities appropriate?

Reply 'yes' to proceed, or let me know what changes you'd like."

Do NOT proceed to Phase 5 until the user explicitly approves.
</stop_for_confirmation>

## Phase 5: Create Tasks in Pyllar

After user approval, create the tasks using the Pyllar MCP tools.

### Step 1: Create the Parent Task

Use `mcp__pyllar__create_task` with:
- `title`: The parent task title
- `description`: Include a summary and list the planned subtasks
- `workspace_id`: From Phase 1
- `task_state_id`: The "Backlog" state ID from Phase 1
- `priority`: As discussed with user (default: "medium")
- `dependencies`: A list of pre-existing task IDs on which this task depends (if any)

Save the returned parent task `id` for use in subtask creation.

### Step 2: Create Subtasks

For each subtask, use `mcp__pyllar__create_task` with:
- `title`: The subtask title
- `description`: Use the **Task Description Template** below
- `workspace_id`: Same as parent
- `task_state_id`: The "Backlog" state ID
- `parent_task_id`: The parent task ID from Step 1
- `priority`: As determined in analysis
- `dependencies`: Array of task IDs that must complete before this task can start

Create subtasks in dependency order (tasks with no dependencies first).

#### Task Description Template

Use this template for all task descriptions:

```markdown
## Objective
[One sentence: what this task accomplishes]

## Context
[Why this is needed, relevant background information]

## Requirements
- [ ] Specific deliverable 1
- [ ] Specific deliverable 2

## Acceptance Criteria
- Given [precondition], when [action], then [expected result]
```

Adapt the template as needed:
- Skip **Context** if the objective is self-explanatory
- Add **Technical Notes** for implementation guidance on complex tasks
- Use multiple acceptance criteria for tasks with distinct behaviors to verify

### Step 3: Output Summary

After all tasks are created, present a summary:

```
## Created Task Hierarchy

**Parent**: [human_id] - [title]

**Subtasks**:
├── [human_id] - [title] (Priority: [priority])
│   └── Dependencies: none
├── [human_id] - [title] (Priority: [priority])
│   └── Dependencies: [human_id of dependency]
└── [human_id] - [title] (Priority: [priority])
    └── Dependencies: [human_ids of dependencies]

All [N] tasks created successfully. Start with [human_id] which has no dependencies.
```

## Guidelines for Good Breakdowns

- **Be specific**: "Implement user model with email validation" not "Set up user stuff"
- **Include context**: Each subtask description should be understandable in isolation
- **Keep scope tight**: If a subtask seems too large, consider breaking it down further
- **Consider testing**: Include testing as a subtask when appropriate
- **Avoid over-engineering**: Only create subtasks for work that actually needs to be done
