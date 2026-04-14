# Agent Platform Feature Roadmap

Detailed implementation plans for high-priority capabilities identified from reviewing [Wippy](https://github.com/wippyai/app) and [Cortex](https://github.com/itsHabib/cortex), mapped to Citadel's existing architecture and design principles.

---

## 1. DAG-Based Workflow Composition

### What It Is

A system for composing multi-step agent workflows as directed acyclic graphs (DAGs). Instead of a single agent executing a single task end-to-end, a workflow defines a graph of steps — each step being an agent action, a validation gate, or a human checkpoint — with explicit data flow between them.

Wippy calls these "dataflows" and supports function nodes, agent nodes, cycle nodes (iterative refinement), and parallel map-reduce nodes. Citadel's version should be opinionated toward software development workflows.

### Why It Matters

Citadel's current execution model is: one task → one agent run → one result. This works for simple tasks but breaks down for anything requiring coordination:

- A feature that needs a migration, backend code, and frontend code
- A bug fix that requires investigation, implementation, and test writing
- A refactor that should be validated incrementally

DAG workflows let a developer describe *how* work should flow, not just *what* work should be done. This is the infrastructure that enables Stage 2 autonomy (human-at-the-gates) from AGENT_DESIGN_PRINCIPLES.md.

### Data Model Changes

#### New Resource: `Citadel.Tasks.Workflow`

```
Workflow
├── id (uuid)
├── name (string) — e.g., "Feature Implementation", "Bug Fix"
├── description (string)
├── workspace_id (uuid, multitenancy attribute)
├── template (boolean, default: false) — reusable workflow templates
├── created_by_id (uuid → User)
└── timestamps
```

#### New Resource: `Citadel.Tasks.WorkflowStep`

```
WorkflowStep
├── id (uuid)
├── workflow_id (uuid → Workflow)
├── name (string) — e.g., "Write Migration", "Run Tests", "Human Review"
├── step_type (enum)
│   ├── :agent — Execute via agent
│   ├── :validation — Run automated checks (tests, linting, etc.)
│   ├── :human_gate — Pause for human decision
│   ├── :parallel — Fan out to multiple sub-steps
│   └── :cycle — Iterative refinement (see Feature #2)
├── config (map) — step-type-specific configuration
│   For :agent → %{model: "claude-sonnet-4-20250514", prompt_template: "...", tools: [...]}
│   For :validation → %{command: "mix test", success_pattern: "0 failures"}
│   For :human_gate → %{question: "Approve migration?", options: ["approve", "reject", "revise"]}
│   For :parallel → %{strategy: "all" | "any"}
│   For :cycle → %{max_iterations: 3, threshold_key: "quality_score", threshold_value: 0.8}
├── position (integer) — ordering within the DAG level
├── workspace_id (uuid)
└── timestamps
```

#### New Resource: `Citadel.Tasks.WorkflowStepEdge`

```
WorkflowStepEdge
├── id (uuid)
├── workflow_id (uuid → Workflow)
├── from_step_id (uuid → WorkflowStep, nullable for entry points)
├── to_step_id (uuid → WorkflowStep, nullable for exit points)
├── condition (map, nullable) — conditional edges
│   e.g., %{field: "status", operator: "eq", value: "approved"}
└── timestamps
```

#### New Resource: `Citadel.Tasks.WorkflowRun`

Tracks execution of a workflow instance (analogous to how `AgentRun` tracks a single task execution).

```
WorkflowRun
├── id (uuid)
├── workflow_id (uuid → Workflow)
├── task_id (uuid → Task) — the parent task being executed
├── status (enum: :pending, :running, :paused, :completed, :failed, :cancelled)
├── current_step_id (uuid → WorkflowStep, nullable)
├── context (map) — accumulated data flowing through the DAG
├── workspace_id (uuid)
├── started_at (datetime)
├── completed_at (datetime)
└── timestamps
```

#### New Resource: `Citadel.Tasks.WorkflowStepRun`

```
WorkflowStepRun
├── id (uuid)
├── workflow_run_id (uuid → WorkflowRun)
├── workflow_step_id (uuid → WorkflowStep)
├── agent_run_id (uuid → AgentRun, nullable) — links to existing agent execution
├── status (enum: :pending, :running, :waiting, :completed, :failed, :skipped)
├── input (map) — data received from upstream steps
├── output (map) — data produced for downstream steps
├── iteration (integer, default: 0) — for cycle steps
├── started_at (datetime)
├── completed_at (datetime)
└── timestamps
```

#### Modifications to Existing Resources

**Task**: Add `workflow_id` (nullable) relationship and `workflow_run_id` (nullable) for the active workflow execution. Tasks without a workflow continue to use the existing single-agent model.

**AgentRun**: Add `workflow_step_run_id` (nullable) to link individual agent executions back to their workflow step.

### Execution Engine

The workflow executor lives in `lib/citadel/tasks/workflow_executor.ex` and orchestrates step execution:

1. **Start**: When a task with an assigned workflow becomes eligible, create a `WorkflowRun` and identify entry-point steps (no incoming edges).
2. **Execute Step**: Based on `step_type`:
   - `:agent` → Create an `AgentRun` and `AgentWorkItem`, reusing the existing claim/execute flow.
   - `:validation` → Execute the configured command in the agent's worktree, record pass/fail.
   - `:human_gate` → Set `WorkflowRun.status` to `:paused`, notify the user, wait for response.
   - `:parallel` → Execute all downstream steps concurrently, wait for all (or any, based on strategy).
   - `:cycle` → Execute the step's sub-workflow, evaluate threshold, loop or proceed.
3. **Advance**: When a step completes, evaluate outgoing edges. If conditions are met, start the next step(s). If multiple edges are satisfied, execute in parallel.
4. **Complete**: When all terminal steps (no outgoing edges) are complete, mark the `WorkflowRun` as `:completed`.

This should be implemented as a GenServer per active workflow run, supervised under a DynamicSupervisor. Steps that create agent runs integrate with the existing `AgentWorkItem` → `AgentRun` flow — the workflow executor simply watches for `AgentRun` completion events via PubSub.

### UI/UX

See **[UI/UX Deep Dive: Configuration and Monitoring](#uiux-deep-dive-configuration-and-monitoring)** for detailed wireframes and interaction flows covering the workflow builder, step configuration, runtime monitoring, and dashboard integration.

**Key surfaces:**
- `/workflows` — Workflow list and builder (structured step list for Phase 1-2, visual canvas for Phase 3)
- `/tasks/:id` — Workflow selector dropdown, live workflow progress panel, human gate inline response
- `/dashboard` — Active workflow runs, "needs attention" badge for paused/failed workflows

### Migration Path

Phase 1: Data model and basic linear workflows (steps execute sequentially, no branching). This alone is useful — a task can have a "write code → run tests → human review" pipeline.

Phase 2: Parallel steps and conditional edges. Enables fan-out/fan-in patterns.

Phase 3: Visual builder. Until then, workflows can be created via templates or the admin interface.

---

## 2. Iterative Refinement Cycles with Quality Thresholds

### What It Is

A mechanism where an agent's output is automatically evaluated against quality criteria, and if it falls below a threshold, the agent iterates — receiving the critique and producing an improved version. The cycle repeats until the output meets the threshold or a maximum iteration count is reached.

Wippy implements this as "cycle nodes" in their dataflow engine, with a separate critique agent (often on a different, cheaper model) evaluating output. The cycle maintains persistent state across iterations.

### Why It Matters

This is the single most important capability for moving from Stage 1 (human reviews everything) to Stage 2 (human reviews what fails validation). From AGENT_DESIGN_PRINCIPLES.md:

> "Every investment in automated validation infrastructure is an investment in reducing mandatory human oversight."

Currently, when an agent produces subpar work, the developer must catch it during review and either reject it or manually fix it. Iterative refinement means the agent catches its own mistakes before the developer ever sees the output. The developer's review becomes a spot-check, not a line-by-line audit.

### Data Model Changes

#### New Resource: `Citadel.Tasks.RefinementCycle`

```
RefinementCycle
├── id (uuid)
├── agent_run_id (uuid → AgentRun)
├── workflow_step_run_id (uuid → WorkflowStepRun, nullable)
├── status (enum: :running, :passed, :failed_max_iterations, :error)
├── max_iterations (integer, default: 3)
├── current_iteration (integer, default: 0)
├── threshold_type (enum)
│   ├── :test_pass — all tests must pass
│   ├── :score — numeric score from evaluator must meet threshold
│   ├── :checklist — all checklist items must be satisfied
│   └── :custom — custom evaluation function
├── threshold_config (map)
│   For :test_pass → %{command: "mix test", required_pattern: "0 failures"}
│   For :score → %{min_score: 0.8, evaluator: "quality_check"}
│   For :checklist → %{items: ["has tests", "no warnings", "docs updated"]}
│   For :custom → %{module: "Citadel.Tasks.Evaluators.SecurityCheck"}
├── workspace_id (uuid)
└── timestamps
```

#### New Resource: `Citadel.Tasks.RefinementIteration`

```
RefinementIteration
├── id (uuid)
├── refinement_cycle_id (uuid → RefinementCycle)
├── iteration_number (integer)
├── evaluation_result (map) — structured evaluation output
│   e.g., %{score: 0.6, passed: false, feedback: "Missing error handling for..."}
├── agent_feedback (string) — critique sent back to agent
├── status (enum: :evaluated, :refined, :accepted)
├── started_at (datetime)
├── completed_at (datetime)
└── timestamps
```

#### Modifications to Existing Resources

**AgentRun**: Add `refinement_cycle_id` (nullable) relationship. Add `iteration_count` (integer, default: 0) for quick display.

**Task**: Add `refinement_config` (map, nullable) — default refinement settings when this task runs. Inherited by agent runs.

### Evaluation Engine

The evaluation engine lives in `lib/citadel/tasks/refinement/` with a behaviour and implementations:

```elixir
# lib/citadel/tasks/refinement/evaluator.ex
defmodule Citadel.Tasks.Refinement.Evaluator do
  @callback evaluate(output :: map(), config :: map()) ::
    {:pass, score :: float()} | {:fail, score :: float(), feedback :: String.t()}
end
```

**Built-in evaluators:**

- `TestEvaluator` — Runs the configured test command in the agent's worktree. Parses output for pass/fail. Feedback is the test failure output.
- `LLMEvaluator` — Sends the agent's diff + task description to a separate LLM call (configurable model, defaults to a cheaper model) with a scoring rubric. Returns numeric score and written feedback.
- `ChecklistEvaluator` — Runs a series of checks (file exists, pattern present, command succeeds) and reports which items pass/fail.
- `CompositeEvaluator` — Combines multiple evaluators with weighted scoring.

### Refinement Loop

Integrated into the agent execution flow in `lib/citadel/tasks/refinement/runner.ex`:

1. Agent completes its work (produces a diff/commit).
2. If the task or workflow step has refinement configured, create a `RefinementCycle`.
3. Run the configured evaluator against the agent's output.
4. If evaluation passes → mark cycle as `:passed`, proceed to next workflow step or completion.
5. If evaluation fails and `current_iteration < max_iterations`:
   - Create a `RefinementIteration` with the evaluation feedback.
   - Send the feedback back to the agent as a new message: "Your work was evaluated and did not meet the quality threshold. Here's the feedback: {feedback}. Please revise."
   - Agent produces a new iteration.
   - Return to step 3.
6. If evaluation fails and `current_iteration >= max_iterations` → mark cycle as `:failed_max_iterations`, escalate to human review.

### UI/UX

See **[UI/UX Deep Dive: Configuration and Monitoring](#uiux-deep-dive-configuration-and-monitoring)** for detailed wireframes and interaction flows covering standalone refinement configuration, the refinement timeline during execution, and the human intervention flow when refinement fails.

**Key surfaces:**
- Task form "Quality Gates" section — Toggle refinement on/off, add evaluators, set max iterations and failure behavior
- `/agent-runs/:id` — Refinement iteration timeline showing score progression, evaluator feedback, and agent revisions
- `/tasks/:id` — Enriched execution status ("Running, iteration 2 of 3"), refinement badges on agent runs
- `/tasks/:id` within workflow — Expandable step detail showing per-iteration scores and the human gate intervention UI when refinement exhausts

### Standalone Usage (Without Workflows)

Refinement cycles work independently of the workflow system. Any task with `agent_eligible: true` and a `refinement_config` will automatically run through the refinement loop after the agent completes its work. This means the feature is useful immediately, even before workflows are implemented.

### Integration with Workflows

When used within a workflow, refinement is not a separate step type — it is a modifier on agent steps. Any agent step in a workflow can have refinement toggled on. When enabled, the agent executes, gets evaluated, and potentially iterates before the workflow advances to the next step. From the workflow executor's perspective, a step with refinement is still a single step that either completes or fails — the refinement loop is encapsulated.

This is a deliberate simplification over Wippy's approach, where cycle nodes are separate DAG nodes containing sub-workflows. Treating refinement as a step modifier is easier to configure, easier to reason about, and matches how developers think about quality gates: "run this step, and make sure it passes these checks before moving on."

---

## How Workflows and Refinement Cycles Work Together

### The Two Modes

#### Mode 1: Standalone Refinement (No Workflow)

The simpler case, ships first. Refinement is configured directly on a task. When an agent finishes its work, the refinement loop kicks in automatically as a post-execution phase of the *same* agent run.

1. Task has `agent_eligible: true` and a `refinement_config`
2. Agent claims the task, does its work, produces a commit in the worktree
3. *Before* the agent run is marked complete, the refinement runner intercepts
4. Evaluator runs against the worktree (tests, LLM review, checklist — whatever's configured)
5. If it fails: feedback is injected into the agent's conversation context, agent revises, evaluator runs again
6. If it passes or hits max iterations: agent run completes with the refinement result attached

The key insight is that refinement happens *within* the agent run, not after it. The agent's process stays alive through the refinement loop. Each iteration is the same agent session receiving new instructions — "your tests failed, here's the output, fix it." This is important because the agent retains its full context from the original task.

#### Mode 2: Workflow-Embedded Refinement

In a workflow, refinement is configured on individual agent steps rather than on the task itself. Different steps can have different refinement configurations — a migration step might only require tests to pass, while an implementation step might require both tests and an LLM review.

1. Workflow executor reaches an agent step that has refinement configured
2. Creates an `AgentRun` and `WorkflowStepRun`, plus a `RefinementCycle` linked to both
3. Agent claims and executes the step
4. Evaluator runs. If pass → step completes, workflow advances to next step(s)
5. If fail → agent iterates within the same step. The `WorkflowStepRun.iteration` counter increments
6. If max iterations exceeded → the step's "on failure" behavior determines what happens:
   - **Route to human gate**: The workflow creates an ad-hoc human gate. The developer sees the best attempt + all evaluation feedback and decides: approve anyway, reject, or provide guidance for another attempt
   - **Fail the step**: The workflow follows the failure edge (if one exists) or fails entirely
   - **Escalate model**: If an escalation chain is configured, retry with a more capable model (resets the iteration counter)

A single workflow step can involve multiple agent iterations, but from the workflow's perspective it's still one step that either completes or fails.

### Example: Feature Implementation Workflow

A concrete example showing how different steps compose with different refinement configs and models:

```
Step 1: Write Migration (agent, Sonnet)
  └── Refinement: Tests only, max 2 iterations
       Command: mix ash.migrate && mix ash.rollback && mix ash.migrate

Step 2: Implement Feature (agent, Sonnet)
  └── Refinement: Composite, max 3 iterations
       - Tests: mix test
       - LLM Review (Haiku): "Does the implementation match the task description?
                               Does it follow Ash patterns? Score 0-1."
         Threshold: 0.7

Step 3: Human Review (human gate)
  └── Shows: final diff, all evaluation scores, iteration history

Step 4: Write Tests (agent, Sonnet)
  └── Refinement: Tests only, max 3 iterations
       Command: mix test test/path/generated_test.exs
```

Each step operates on the same worktree. Step 2's agent sees the migration files from Step 1. Step 4's agent sees all the code from Steps 1 and 2. The worktree accumulates changes as the workflow progresses.

### Data Flow Between Steps

Each step produces structured output stored in `WorkflowStepRun.output`. The workflow run maintains a `context` map that accumulates these outputs as steps complete.

For agent steps, the output is:
- `diff` — the git diff produced by this step
- `files_changed` — list of modified file paths
- `test_results` — if refinement ran tests, the results
- `evaluation_scores` — final scores from all evaluators
- `iteration_count` — how many refinement iterations occurred

For human gate steps, the output is:
- `decision` — approve, reject, or guidance
- `feedback` — the developer's text (if any)

The next step's agent receives this accumulated context in its prompt via template variables. The prompt template for a step can reference upstream data: `{previous_step.diff}`, `{previous_step.files_changed}`, `{context.migration_output}`. This is how "Write Tests" knows what code was written in "Implement Feature" — it receives the diff and file list as context.

A conditional edge after a human gate can check `decision == "approve"` to branch the workflow — for example, routing to a "Revise" step if the reviewer rejects.

### Failure Escalation Path

When refinement exhausts its iterations, the system follows this escalation path:

1. **Within the refinement loop**: Agent iterates up to `max_iterations`, receiving evaluator feedback each time
2. **On refinement failure**: Check the step's "on failure" config:
   - If "escalate model" and an escalation chain is configured → retry the entire step with a more capable model (e.g., Sonnet → Opus), reset iteration counter
   - If "route to human gate" → pause the workflow, present the best attempt to the developer with all evaluation history
   - If "fail" → mark the step as failed, follow failure edges or fail the workflow
3. **At the human gate**: Developer can approve as-is, reject entirely, or provide written guidance and grant one more iteration — the agent gets the developer's specific instructions injected into its context

This means a step could potentially go through: 3 iterations with Sonnet → model escalation → 3 iterations with Opus → human gate with developer guidance → 1 final iteration. The entire history is preserved and visible in the UI.

---

## UI/UX Deep Dive: Configuration and Monitoring

### Workflow Builder

The workflow builder is a structured form (Phase 1-2), not a freeform canvas (Phase 3). It renders steps as a vertical list since Phase 1 only supports linear flows.

**Entry point**: `/workflows` page shows a list of workspace workflows. "New Workflow" button offers two paths:
1. **Start from template** — pick a pre-built workflow (Feature, Bug Fix, Refactor)
2. **Start from scratch** — empty builder

**The builder layout:**

```
┌─ Workflow: Feature Implementation ───────────────────────────┐
│                                                               │
│  Description: [ Standard feature workflow with migration,   ] │
│               [ implementation, and test writing             ] │
│                                                               │
│  ┌─ Steps ──────────────────────────────────────────────────┐ │
│  │                                                           │ │
│  │  1. ◆ Write Migration                          [···]  ↕  │ │
│  │     Agent · claude-sonnet · Refinement: Tests (2x)        │ │
│  │                                                           │ │
│  │  2. ◆ Implement Feature                        [···]  ↕  │ │
│  │     Agent · claude-sonnet · Refinement: Composite (3x)    │ │
│  │                                                           │ │
│  │  3. ◇ Review Implementation                    [···]  ↕  │ │
│  │     Human Gate · "Review the implementation"              │ │
│  │                                                           │ │
│  │  4. ◆ Write Tests                              [···]  ↕  │ │
│  │     Agent · claude-sonnet · Refinement: Tests (3x)        │ │
│  │                                                           │ │
│  │  [ + Add Step ]                                           │ │
│  │                                                           │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                               │
│  [ Save as Template ]                    [ Save ]  [ Cancel ] │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

- `◆` = agent step, `◇` = human gate, `▣` = validation step
- `↕` = drag handle for reordering
- `[···]` = kebab menu (edit, duplicate, delete)
- Each collapsed step shows a one-line summary: type, model, refinement config

**Clicking a step expands it inline** to show its full configuration:

```
┌─ 2. ◆ Implement Feature ────────────────────────────────────┐
│                                                               │
│  Name:  [ Implement Feature                               ]  │
│  Type:  [ Agent Step ▾ ]                                     │
│                                                               │
│  ┌─ Agent Configuration ─────────────────────────────────┐   │
│  │  Model:   [ Workspace Default (claude-sonnet) ▾ ]     │   │
│  │  Prompt:  [ Implement the feature described in the    ] │   │
│  │           [ task. Follow existing patterns in the     ] │   │
│  │           [ codebase. {task.description}              ] │   │
│  │  Tools:   [x] Task management  [ ] GitHub  [x] MCP    │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌─ Quality Gates ───────────────────────────────────────┐   │
│  │  [x] Enable auto-refinement                           │   │
│  │                                                        │   │
│  │  Evaluator 1: [ Tests ▾ ]                             │   │
│  │    Command: [ mix test                              ]  │   │
│  │                                                        │   │
│  │  Evaluator 2: [ LLM Review ▾ ]                        │   │
│  │    Model:     [ claude-haiku ▾ ]                       │   │
│  │    Rubric:    [ Does the implementation match the   ]  │   │
│  │               [ task requirements? Are Ash patterns ]  │   │
│  │               [ followed correctly?                 ]  │   │
│  │    Threshold: [====●=====] 0.7                        │   │
│  │                                                        │   │
│  │  [ + Add evaluator ]                                   │   │
│  │                                                        │   │
│  │  Max iterations: [ 3 ▾ ]                              │   │
│  │  On failure: [ Pause for human review ▾ ]             │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌─ Data Flow ───────────────────────────────────────────┐   │
│  │  Input from previous step:                             │   │
│  │    migration_files → context.migration_output          │   │
│  │  Output to next step:                                  │   │
│  │    diff, test_results, evaluation_scores               │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                               │
│                                              [ Collapse ▲ ]  │
└───────────────────────────────────────────────────────────────┘
```

The **Quality Gates** section within each agent step is the same UI as standalone task refinement — the configuration is identical, just scoped to the step instead of the task. When a task has a workflow assigned, the task-level refinement config is ignored in favor of per-step configs.

The **Data Flow** section shows what data this step receives from upstream and what it produces for downstream steps. For Phase 1 this is mostly informational — the system automatically passes the previous step's output. In later phases, users could map specific fields.

### Task-Level Standalone Refinement Configuration

For tasks without a workflow, refinement is configured on the task form itself:

```
┌─ Quality Gates ──────────────────────────────────────────────┐
│                                                               │
│  [x] Enable auto-refinement                                  │
│                                                               │
│  Evaluator:  [ Tests ▾ ]                                     │
│                                                               │
│  ┌─ Test Configuration ──────────────────────────────────┐   │
│  │  Command:    [ mix test                            ]  │   │
│  │  Run in:     (•) Agent worktree  ( ) CI               │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                               │
│  Max iterations:  [ 3 ▾ ]                                    │
│                                                               │
│  If max iterations exceeded:                                 │
│    (•) Pause for human review                                │
│    ( ) Accept best attempt                                   │
│    ( ) Fail the task                                         │
│                                                               │
│  [ + Add another evaluator ]                                 │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

Clicking "+ Add another evaluator" adds a second evaluator card. Multiple evaluators run as a composite — all must pass. This is how you combine "tests must pass" with "LLM review must score above 0.7."

The evaluator dropdown options and their config panels:

- **Tests** — Command input, success pattern (defaults derived from project — `mix test` for Elixir, `npm test` for JS, etc.)
- **LLM Review** — Model selector (defaults to a cheaper model than the agent), rubric textarea where the user describes what "good" looks like, score threshold slider (0.0–1.0)
- **Checklist** — Dynamic list of named checks, each with a type (command, file exists, pattern grep) and config
- **Custom** — Module name input for teams that write their own evaluator behaviour

### Runtime Monitoring: Workflow Progress

When a workflow is running, the task detail page (`/tasks/:id`) shows a live progress view:

```
┌─ Workflow Progress ──────────────────────────────────────────┐
│                                                               │
│  ✓ Write Migration          00:42  Score: —  Iterations: 1   │
│  ● Implement Feature        02:15  Score: 0.6  Iter: 2 of 3 │
│  ○ Review Implementation    —      —                          │
│  ○ Write Tests              —      —                          │
│                                                               │
│  ✓ = complete  ● = running  ○ = pending  ⚠ = needs attention │
└───────────────────────────────────────────────────────────────┘
```

Clicking the running step expands to show the refinement timeline:

```
┌─ ● Implement Feature — Iteration 2 of 3 ────────────────────┐
│                                                               │
│  Iteration 1                                       Score: 0.4 │
│  ├─ Agent produced 247 lines across 4 files                   │
│  ├─ Tests: 3 passed, 2 failed                                │
│  │   ✗ test "creates task with valid params"                  │
│  │   ✗ test "returns error for invalid state"                 │
│  ├─ LLM Review: 0.5 — "Missing error handling for the       │
│  │   case where workspace_id is nil. The create action       │
│  │   should validate workspace membership."                   │
│  └─ Feedback sent → agent revising...                         │
│                                                               │
│  Iteration 2 (current)                               Score: — │
│  ├─ Agent revised 3 files                                     │
│  ├─ Tests: running...                                         │
│  └─ LLM Review: pending                                      │
│                                                               │
│  [ View full agent output ]  [ View diff ]                    │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

### Runtime Monitoring: Refinement Failure and Human Intervention

When refinement exhausts its iterations and routes to a human gate:

```
┌─ ⚠ Implement Feature — Needs Review ────────────────────────┐
│                                                               │
│  Refinement exhausted after 3 iterations.                    │
│  Best score: 0.7 (threshold: 0.8)                            │
│                                                               │
│  Remaining issue (from last evaluation):                     │
│  "The pagination implementation uses offset-based paging     │
│   but the project convention is keyset pagination. The agent │
│   corrected the test failures but didn't address this."      │
│                                                               │
│  [ View Diff ]  [ View All Iterations ]                      │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  What would you like to do?                              │ │
│  │                                                          │ │
│  │  [ Approve as-is ]  [ Reject ]  [ Give guidance ▾ ]     │ │
│  │                                                          │ │
│  │  Guidance: [ Switch to keyset pagination using          ]│ │
│  │            [ Ash.Query.page/2 as shown in the           ]│ │
│  │            [ existing list_tasks action.                 ]│ │
│  │                                                          │ │
│  │                              [ Send & retry (1 more) ]   │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

"Give guidance" is the human-in-the-loop moment. The developer provides specific instructions, and the agent gets one more attempt with that guidance injected into its context. This is the "human gates as the killer feature" principle from Kilroy — the agent works autonomously until it genuinely needs a decision.

The three response options:
- **Approve as-is**: Accept the current output despite not meeting the threshold. Workflow advances.
- **Reject**: Fail the step. Workflow follows the failure edge or fails entirely.
- **Give guidance**: Developer writes specific instructions. Agent gets one additional iteration with the developer's feedback prepended. If it passes after this attempt, the workflow advances. If it fails again, the developer is asked once more (no infinite loops — this is a single bonus attempt).

### Dashboard Integration

On the main dashboard (`/dashboard`):

- **Active workflow runs** section showing all in-progress workflows across tasks
- **Needs attention** badge: count of workflows paused at human gates or failed refinement
- **Filter by status**: running, paused (human gate), failed, completed
- Clicking a workflow run navigates to the task detail page with the workflow progress panel open

---

## 3. Per-Step Model Configuration

### What It Is

The ability to assign different AI models to different stages of work — within a single task execution or across workflow steps. A planning phase might use a high-capability model (Claude Opus), code generation might use a balanced model (Claude Sonnet), and a quick validation check might use a fast/cheap model (Claude Haiku or GPT-4o-mini).

Wippy implements this by letting each agent node in a dataflow specify its own model independently. Their writer/critic pattern explicitly uses different providers (GPT for writing, Grok for critique) to get diverse perspectives.

### Why It Matters

From AGENT_DESIGN_PRINCIPLES.md's "Model Escalation Saves Money" principle (from Kilroy):

> "Kilroy starts with cheaper models and escalates to more capable ones only after failures. This is a simple but effective cost optimization that also tends to produce faster results for easy tasks."

Currently, Citadel uses a single default provider and model for all AI operations. This means every task — whether it's renaming a variable or designing a new architecture — uses the same model at the same cost. Per-step model configuration enables:

- **Cost optimization**: Use Haiku for validation checks, Sonnet for code generation, Opus for complex planning.
- **Speed optimization**: Cheaper models are faster. Quick tasks finish sooner.
- **Quality optimization**: Some tasks genuinely need the best model. Others don't.
- **Diverse evaluation**: Using a different model (or provider) for critique reduces the chance of systematic blind spots.

### Data Model Changes

#### New Resource: `Citadel.Tasks.ModelConfig`

```
ModelConfig
├── id (uuid)
├── name (string) — e.g., "Default", "Cost-Optimized", "High-Quality"
├── workspace_id (uuid)
├── provider (enum: :anthropic, :openai)
├── model (string) — e.g., "claude-sonnet-4-20250514", "gpt-4o-mini"
├── temperature (float, default: 0.7)
├── max_tokens (integer, nullable)
├── is_default (boolean, default: false) — workspace default
└── timestamps
```

#### New Resource: `Citadel.Tasks.ModelEscalationChain`

```
ModelEscalationChain
├── id (uuid)
├── name (string) — e.g., "Standard Escalation"
├── workspace_id (uuid)
├── steps (list of maps, ordered)
│   [
│     %{model_config_id: "...", max_attempts: 2},
│     %{model_config_id: "...", max_attempts: 1}
│   ]
└── timestamps
```

#### Modifications to Existing Resources

**WorkflowStep** (`config` map): Add `model_config_id` field to agent and cycle step configs. If not set, falls back to task-level, then workspace-level default.

**Task**: Add `model_config_id` (nullable) — task-level model override.

**AgentRun**: Add `model_config_id` (nullable) — records which model was actually used. Add `escalated_from_id` (nullable, self-referential) — links to the previous failed run if this run is an escalation.

**RefinementCycle** (from Feature #2): Add `evaluator_model_config_id` (nullable) — allows the evaluator LLM to use a different model than the agent.

### Escalation Logic

Implemented in `lib/citadel/tasks/model_escalation.ex`:

1. Agent run starts with the configured model (step → task → workspace default).
2. If the run fails (error, not just bad output):
   - Check if an escalation chain is configured.
   - If yes, find the next step in the chain.
   - Create a new `AgentRun` with the escalated model, linked via `escalated_from_id`.
   - Re-queue the work item.
3. If the run produces output that fails refinement after max iterations:
   - Optionally escalate to a more capable model and retry the entire refinement cycle.
   - Configurable: "escalate on refinement failure" toggle.

### Changes to AI Integration Layer

#### `Citadel.AI.Config` Updates

```elixir
# Current: single default provider
def default_provider, do: Application.get_env(:citadel, __MODULE__)[:default_provider]

# New: resolve model config from context
def resolve_model_config(opts) do
  # Priority: explicit opts > workflow step > task > workspace default
  cond do
    opts[:model_config] -> opts[:model_config]
    opts[:model_config_id] -> Citadel.Tasks.get_model_config!(opts[:model_config_id])
    opts[:task_id] -> resolve_from_task(opts[:task_id])
    opts[:workspace_id] -> resolve_workspace_default(opts[:workspace_id])
    true -> system_default()
  end
end
```

#### `Citadel.AI.Client` Updates

The `create_chain/2` function already accepts model options. The change is to thread `ModelConfig` through the call chain:

- `WorkflowExecutor` passes `model_config_id` from the step config when creating an agent run.
- `AgentRun` stores the resolved model config.
- When the agent claims and executes, it receives the model config in the claim response and uses it for LLM calls.

### UI/UX

#### Workspace Settings (New Section: Model Configuration)

Under `/preferences/workspace`:

- **Model Configurations** list:
  - Each entry shows: name, provider icon, model name, temperature.
  - "Add Configuration" button opens a form:
    - Name (text input)
    - Provider (dropdown: Anthropic, OpenAI)
    - Model (dropdown, filtered by provider — populated from known models)
    - Temperature (slider, 0.0–1.0)
    - Max tokens (optional number input)
  - Star icon to set as workspace default.

- **Escalation Chains** list:
  - Each entry shows: name, chain visualization (Model A → Model B → Model C).
  - "Add Chain" button opens a form:
    - Name (text input)
    - Ordered list of steps: model config dropdown + max attempts input. Add/remove/reorder steps.

#### Task Configuration

On the task creation/edit form:

- **Model** dropdown (in the "Agent Settings" group alongside refinement):
  - Options: "Workspace Default", plus all workspace model configs.
  - Shows provider icon + model name + cost indicator ($ / $$ / $$$).

- **Escalation** dropdown:
  - Options: "None", plus all workspace escalation chains.

#### Workflow Builder

On each agent step card in the workflow builder:

- **Model badge**: Shows the configured model (or "Default" if inherited).
- Click to configure: opens model selector dropdown.
- On cycle steps: separate model selector for the evaluator model.

#### Agent Run Detail

On the agent run page (`/agent-runs/:id`):

- **Model info** in the run header: Provider icon + model name + badge if escalated.
- If escalated: "Escalated from [previous run link] (model X failed after N attempts)".
- **Cost tracking** (future): Token usage and estimated cost per run, broken down by model.

#### Dashboard

- **Model usage summary** (optional, future): Pie chart of model usage across runs. Cost per model. Success rate per model.

### Migration Path

Phase 1: `ModelConfig` resource and workspace-level defaults. Thread model config through `AI.Client`. This alone lets workspaces switch their default model without code changes.

Phase 2: Task-level and workflow-step-level model overrides. The UI for selecting models on tasks and workflow steps.

Phase 3: Escalation chains. Automatic retry with model upgrades on failure.

---

## 4. Agent Reliability & Observability (from Cortex)

Insights from [Cortex](https://github.com/itsHabib/cortex), an Elixir/OTP multi-agent orchestration system that spawns Claude CLI processes and coordinates them via DAG workflows, mesh networking, or gossip protocols. Built on the same tech stack as Citadel (Elixir, Phoenix LiveView, Ecto), making its patterns directly transferable.

### 4.1 Stall Detection Watchdog

**What Cortex does:** Monitors spawned agent processes every 2 minutes and flags teams silent for 5+ minutes. Uses OS-level `kill -0` checks and a SWIM-inspired alive/suspect/dead state machine to detect silently hung processes.

**Why it matters:** A silently hung agent that wastes hours is the fastest way to lose developer trust. AGENT_DESIGN_PRINCIPLES.md already calls for stall detection (from Kilroy). Cortex provides a concrete implementation pattern on the same tech stack.

**Citadel implementation:** A GenServer that monitors active agent runs by tracking the timestamp of their last activity (updated by stream events and API calls). After a configurable timeout, transitions the run through suspect → stalled → timed_out states. Stalled runs surface prominently in the dashboard and on the task detail page.

### 4.2 Run Diagnosis Engine

**What Cortex does:** `LogParser` parses Claude CLI NDJSON output into structured reports. The diagnosis engine categorizes outcomes: successful completion, max turn limits reached, execution errors, session expiration, crashes during tool execution, incomplete logs. Each diagnosis carries a code and recommended action.

**Why it matters:** Citadel's `StreamParser` parses events for display but doesn't classify run outcomes. "Failed" is not actionable — "hit context limit after 47 tool calls" is. Diagnosis classification also informs automatic retry decisions and refinement cycle behavior.

**Citadel implementation:** A `Citadel.Tasks.RunDiagnosis` module that analyzes AgentRunEvents and stream data to classify run outcomes. Categories: `:completed_clean`, `:completed_with_warnings`, `:hit_context_limit`, `:crashed_during_tool_use`, `:stalled_no_output`, `:timed_out`, `:cancelled_by_user`, `:rate_limited`. The diagnosis is stored on the AgentRun record and displayed as a human-readable banner on the agent run page (e.g., "This run hit the context window limit after 47 tool calls. Consider breaking this task into smaller subtasks.").

### 4.3 Informed Retry (Resume Context from Prior Run)

**What Cortex does:** `LogParser.build_restart_context/1` generates a human-readable summary of prior session activity — what was accomplished, where it stopped, why it failed — and injects this into the resumed prompt. This turns "retry" from "start over" into "continue where you left off."

**Why it matters:** When an agent run fails partway through, the developer's options today are: retry (starts from scratch, may repeat 30 minutes of work) or manually fix it. An informed retry that carries forward structured context from the prior attempt — what files were changed, what tests passed, what the diagnosis was — is dramatically more useful.

**Citadel implementation:** When an agent run fails or times out, a "Retry with context" action on the agent run page creates a new AgentRun linked to the prior run via a `retried_from_id` relationship. The claim API includes structured context from the prior run: diagnosis, files changed, test results, refinement iteration history, and error details. The agent receives this as part of its task context rather than starting blind.

### 4.4 Verify Commands in Refinement Config

**What Cortex does:** YAML configs support a `verify` field per task containing shell commands (e.g., `test -f requirements.md`, `grep -q 'GET' api-design.md`). The orchestrator runs these to verify agents actually produced expected deliverables.

**Why it matters:** Even before the full agent-side generic evaluator is built, lightweight shell assertions give immediate value. "Did the agent create the migration file?" is a more useful check than "did the agent exit cleanly?" These commands can be run by the agent as part of its refinement loop, or by the server as a post-completion check.

**Citadel implementation:** Extend the `refinement_config` map on tasks to support an optional `verify_commands` list:
```
%{
  "enabled" => true,
  "max_iterations" => 3,
  "on_failure" => "pause_for_review",
  "verify_commands" => [
    "mix compile --warnings-as-errors",
    "mix test --failed",
    "test -f priv/repo/migrations/*_add_model_config.exs"
  ]
}
```

The agent receives these in the claim response and runs them as part of its evaluation. The results are reported back via the refinement iteration API. This is a simpler, deterministic complement to the AI-powered generic evaluator.

### 4.5 Event Sink for Automatic PubSub Persistence

**What Cortex does:** `Store.EventSink` is a GenServer that subscribes to all PubSub events and persists them to SQLite automatically. Every event producer gets persistence for free — no explicit save calls needed.

**Why it matters:** Citadel has PubSub for agent events, but persistence requires explicit calls at each event source. An event sink provides a complete audit trail with zero caller effort and ensures no events are lost even if the UI isn't connected.

**Citadel implementation:** A `Citadel.Tasks.EventSink` GenServer that subscribes to agent-related PubSub topics (`tasks:agent_runs:*`, `tasks:refinement:*`, `agent_run_output:*`) and persists events to the AgentRunEvent resource. Started under the application supervisor. Events are batched (flush every 1-2 seconds or every N events) to avoid overwhelming the database during high-activity runs.

---

## Implementation Sequencing

These features have dependencies between them:

```
Phase 1 (Independent, can be parallel):
├── Model Configuration (workspace defaults + task-level overrides)
├── Refinement Cycles (standalone, no workflow dependency)
├── Stall Detection Watchdog (standalone)
├── Event Sink (standalone)
└── Verify Commands in Refinement Config (extends refinement config)

Phase 1.5 (Depends on Phase 1):
├── Run Diagnosis Engine (benefits from refinement + event data)
└── Informed Retry (depends on diagnosis engine)

Phase 2 (Depends on Phase 1):
└── DAG Workflows (linear pipelines first)
    ├── Uses Model Configuration for per-step models
    └── Uses Refinement Cycles for cycle step type

Phase 3 (Depends on Phase 2):
├── Workflow visual builder UI
├── Escalation chains (model + refinement integration)
├── Parallel step execution
└── Conditional edges
```

Model Configuration, Refinement Cycles, Stall Detection, and Event Sink can all ship independently. Verify Commands extends the refinement config work. Diagnosis Engine and Informed Retry build on the event and refinement data from Phase 1. Workflows build on everything.

---

## Task Tracking

### Phase 1 — Created (Server-Side Only)

These tasks have been created in Citadel under parent task **P-123**:

| Task | Title | Dependencies | Status |
|------|-------|-------------|--------|
| P-124 | ModelConfig resource & domain actions | None | Backlog |
| P-125 | RefinementCycle & RefinementIteration resources | None | Backlog |
| P-126 | Task model config & refinement config attributes | P-124 | Backlog |
| P-127 | Agent claim API: include model & refinement config | P-126, P-125 | Backlog |
| P-128 | Agent API: refinement iteration reporting endpoints | P-125 | Backlog |
| P-129 | Workspace preferences UI: model configuration | P-124 | Backlog |
| P-130 | Task detail UI: model selector & refinement config | P-126 | Backlog |
| P-131 | Agent run detail UI: refinement timeline | P-125, P-128 | Backlog |

### Phase 1 — Created (Reliability & Observability, from Cortex)

These tasks have been created in Citadel under parent task **P-123**:

| Task | Title | Dependencies | Status |
|------|-------|-------------|--------|
| P-132 | Stall detection watchdog for agent runs | None | Backlog |
| P-133 | Event sink for automatic PubSub persistence | None | Backlog |
| P-134 | Verify commands in task refinement config | P-126 | Backlog |

### Phase 1.5 — Created (Diagnosis & Retry, from Cortex)

| Task | Title | Dependencies | Status |
|------|-------|-------------|--------|
| P-135 | Run diagnosis engine | P-125, P-132 | Backlog |
| P-136 | Informed retry with prior run context | P-135 | Backlog |

### Phase 1 — Not Yet Created (Agent-Side)

These tasks still need to be planned and created. They cover the agent CLI changes needed to actually execute refinement loops using the server-side infrastructure built above.

- **Agent-side generic evaluator**: The core evaluator that inspects the project (AGENTS.md, CLAUDE.md, package.json, mix.exs, Makefile, etc.) to discover and run validation commands (linting, formatting, security checks, unit tests). Should be language/framework agnostic.
- **Agent-side refinement loop**: Logic in the agent CLI to execute the refinement cycle — run evaluator after completing work, parse results, self-correct based on feedback, report iterations to server via the new API endpoints.
- **Agent-side model config consumption**: Update the agent CLI to read the `model_config` from the claim response and use the specified provider/model for LLM calls instead of its default.

### Phase 2 — Not Yet Created (DAG Workflows)

Everything under **Feature 1: DAG-Based Workflow Composition** still needs tasks:

- Workflow, WorkflowStep, WorkflowStepEdge resources and domain actions
- WorkflowRun and WorkflowStepRun execution tracking resources
- Workflow executor GenServer (orchestrates step execution, PubSub integration)
- Task modifications (workflow_id, workflow_run_id relationships)
- AgentRun modifications (workflow_step_run_id relationship)
- Agent claim API updates for workflow-aware task claiming
- Workflow list page (`/workflows`)
- Workflow builder UI (structured step list for Phase 2, visual canvas for Phase 3)
- Task detail UI: workflow selector and workflow progress panel
- Dashboard: active workflow runs and "needs attention" badge
- Human gate response UI (inline on task detail page)

### Phase 3 — Not Yet Created

- ModelEscalationChain resource and domain actions
- Escalation logic (auto-retry with model upgrade on failure/refinement failure)
- Escalation chain management UI in workspace preferences
- Task/workflow step escalation chain selector UI
- Workflow parallel step execution
- Workflow conditional edges
- Visual workflow builder (canvas-based DAG editor)