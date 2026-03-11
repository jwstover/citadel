# Future Enhancements

Enhancements informed by research into similar tools (notably [Kilroy](https://github.com/danshapiro/kilroy)) that are valuable but not required for the MVP pivot. These should be revisited as the core agent loop matures.

---

## Execution Resilience

### Checkpoint / Resume
Persist execution state after each meaningful step so interrupted runs can resume rather than restart from scratch.

- Save a `checkpoint.json` per agent run (current step, context, git SHA)
- Store checkpoints in Citadel so runs can resume even if the agent machine changes
- Checkpoint commits in git: `citadel(<run_id>): <step> (<status>)`
- Resume reconstructs state from checkpoint + git history

**When to build:** Once agent runs become long enough (multi-step tasks, planning pipelines) that restarting from scratch is wasteful.

### Retry with Model Escalation
Failed tasks retry with configurable budgets. After consecutive failures, automatically escalate to more capable (and more expensive) models.

- Per-task and project-level `max_retries` configuration
- Escalation chain: e.g., Haiku → Sonnet → Opus
- Classify failures as transient (retry same model) vs. deterministic (escalate or fail)

**When to build:** After we have enough agent run data to understand failure patterns.

---

## Observability

### Rich Event Taxonomy
Expand the MVP's basic event types into a full taxonomy for deep execution insight:

- `prompt_sent` / `response_received` — What was sent to and received from the LLM
- `tool_call` / `tool_result` — Individual tool invocations within Claude Code
- `test_started` / `test_passed` / `test_failed` — Test execution detail
- `git_checkpoint` — Commit created during execution
- `stage_retrying` — Retry with context on why

### Per-Stage Artifact Storage
Store structured artifacts for each execution stage:

- `prompt.md` — The exact prompt sent to the LLM
- `response.md` — The full LLM response
- `diff.patch` — Git diff produced by the stage
- `test_output.log` — Test runner output
- `cli_invocation.json` — Exact CLI arguments used

**When to build:** When the review UI needs to answer "what exactly did the agent do and why?"

### Run Archive
Package completed runs into downloadable archives (`run.tgz`) with all artifacts, events, and metadata for offline review or compliance.

---

## Pipeline Execution

### Task Dependency Graphs (DAG)
Model tasks as a directed acyclic graph rather than a flat list. Node types could include:

- **Coding task** — Agent writes code
- **Test task** — Agent runs/writes tests
- **Conditional** — Branch based on previous results (e.g., "if tests pass, create PR; else retry")
- **Human gate** — Pause and ask the developer a question mid-execution
- **Shell command** — Run a specific command (build, lint, deploy)
- **Parallel fan-out / fan-in** — Split work across multiple agents, merge results

This is the foundation for the Phase 4 planning workflow.

### Human Gates
Allow agents to pause mid-execution and ask the developer a question when they hit an ambiguity or decision point.

- Surface as a notification in Citadel UI
- Support timeout with default choice fallback
- Answers flow back to the agent to continue execution

**This is central to the "dev lead managing AI workers" vision** — it's how agents escalate to their human lead.

### Pipeline Definition from English
AI-assisted conversion of natural language feature descriptions into executable task graphs. (Kilroy uses Graphviz DOT format for this; Citadel would use its own task model.)

---

## Multi-Agent

### Git Worktree Isolation for Parallel Agents
When multiple agents work on the same repo simultaneously, each gets its own git worktree and branch. A merge step handles combining results.

- Worker pool with configurable max parallelism
- Merge conflict detection and resolution strategy (auto-retry, human gate, or fail)
- Join policies: wait for all, proceed on first success, etc.

### Agent Identity and Capability
Different agents could have different configurations:

- Model preferences and escalation chains
- Allowed tools and permissions
- Specializations (frontend, backend, testing, docs)

---

## Developer Experience

### Preflight / Dry Run Mode
Validate everything (provider connectivity, model availability, repo access, Citadel auth) without starting actual execution. Produces a readiness report.

The MVP includes a basic preflight check; this expands it into a full diagnostic tool.

### Detached Execution
Long-running agent tasks survive terminal closure. The agent reports progress to Citadel regardless of whether the user is actively watching.

### Skills System
Reusable instruction sets that guide agents during specific task types. Skills encode project conventions, coding standards, and domain knowledge.

- Per-project skills (e.g., "how we write tests", "API conventions")
- Shared skills across workspaces
- Skills attached to task types or pipeline stages

---

## Prior Art Reference

| Pattern | Source | Citadel Adaptation |
|---------|--------|--------------------|
| DAG pipeline execution | Kilroy (Graphviz DOT) | Task dependency graph in Citadel's data model |
| Git worktree isolation | Kilroy | Per-agent worktrees for parallel safety |
| Checkpoint/resume | Kilroy (checkpoint.json + CXDB) | Citadel-stored execution state |
| Model escalation on retry | Kilroy (escalation_models) | Project-level escalation chain config |
| Human gates | Kilroy (WaitHumanHandler) | Notification-driven human-in-the-loop |
| Structured event log | Kilroy (progress.ndjson + CXDB events) | Typed events in Citadel DB |
| Stall watchdog | Kilroy (runStallWatchdog) | Agent-side idle timeout |
| Preflight validation | Kilroy (--preflight) | Agent readiness check |
| Three-layer observability | Kilroy (files → ndjson → CXDB) | Events → Citadel DB → UI |
