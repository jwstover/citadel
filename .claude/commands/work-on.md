---
argument-hint: <task-id>
description: Start working on a Citadel task by its human-readable ID (e.g., PER-155)
---

# Work on Task: $ARGUMENTS

You are starting work on a Citadel task. Follow this workflow to ensure consistent, high-quality implementation.

## Phase 1: Task Discovery

Fetch the task and understand its context:

1. **Fetch the task** using `mcp__citadel-dev__list_tasks` with filter:
   ```json
   {"human_id": {"eq": "$ARGUMENTS"}}
   ```

2. **Check for sub-tasks** by filtering with the task's UUID:
   ```json
   {"parent_task_id": {"eq": "<task_uuid>"}}
   ```

3. **Check for parent task** if the task has a `parent_task_id` - fetch the parent to understand broader context.

4. **Review the task details**:
   - Title and description
   - Priority level
   - Current state
   - Due date (if any)
   - Sub-tasks (if any)

If the task cannot be found, inform the user and stop.

## Phase 2: Preparation

Before writing any code:

1. **Read project conventions**: Review `CLAUDE.md` and `AGENTS.md` to understand project patterns and requirements.

2. **Analyze the task**: Break down the task description into concrete implementation steps using `TodoWrite`.

3. **Research the codebase**: Use the Explore agent or search tools to understand:
   - Existing patterns relevant to this task
   - Files that will need modification
   - Related functionality to maintain consistency with

4. **Clarify ambiguities**: If requirements are unclear, ask the user before proceeding. Do not make assumptions about:
   - Architectural decisions
   - UI/UX choices
   - Business logic edge cases

## Phase 3: Update Task State

Before beginning implementation:

1. **Update the task to "In Progress"** using `mcp__citadel-dev__update_task`:
   - First fetch task states with `mcp__citadel-dev__list_task_states` to get the "In Progress" state ID
   - Update the task with the new `task_state_id`

2. **Create a feature branch** (if not already on one):
   ```bash
   git checkout -b feat/$ARGUMENTS-<short-description>
   ```

## Phase 4: Implementation

Follow these principles while implementing:

1. **Test-Driven Development**: Write tests before implementation when applicable.

2. **Incremental progress**: Update `TodoWrite` items as you complete each step.

3. **Small commits**: Make focused commits with messages referencing the task ID:
   ```
   feat($ARGUMENTS): <description of change>
   ```

4. **Follow project conventions**:
   - Use Ash code interfaces, not direct `Ash.create!/2` calls
   - Load relationships explicitly before using them
   - Pass actor via options: `SomeDomain.action!(..., actor: user)`
   - Use generators in tests: `generate(user())` not manual creation

5. **Avoid over-engineering**: Only implement what the task requires. Do not add:
   - Unrequested features
   - Speculative abstractions
   - Unnecessary refactoring

## Phase 5: Verification

Before marking complete:

1. **Run quality checks**:
   ```bash
   mix ck
   ```

2. **Run tests**:
   ```bash
   mix test
   ```

3. **Verify acceptance criteria**: Confirm all requirements from the task description are met.

## Phase 6: Completion

When implementation is complete and verified:

1. **Update the task to "Complete"** using `mcp__citadel-dev__update_task` with the "Complete" state ID.

2. **Update task description** (if needed) with implementation notes or decisions made.

3. **Summarize work done**: Provide a brief summary of:
   - What was implemented
   - Key decisions made
   - Any follow-up items or considerations

## Handling Blockers

If you cannot complete the task:

1. **Do not mark as complete** - leave in "In Progress" state.

2. **Document the blocker** in the task description using `mcp__citadel-dev__update_task`.

3. **Inform the user** about:
   - What is blocking progress
   - What information or decisions are needed
   - Suggested next steps

---

Begin by fetching task **$ARGUMENTS** now.
