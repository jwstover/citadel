# Agent Design Principles

Insights and guiding principles for Citadel's agent execution model, informed by research into [Kilroy](https://github.com/danshapiro/kilroy) and the emerging patterns in AI-assisted software development.

---

## Key Learnings from Kilroy

### 1. Isolation is Non-Negotiable

Kilroy runs every task in an isolated git worktree — never the developer's working tree. Parallel branches get their own worktrees. This isn't a convenience; it's a safety guarantee. An agent that modifies the developer's working directory is an agent the developer can't trust.

**Citadel application:** Git worktree isolation from day one (P-24). Every agent run gets its own worktree. The developer's main checkout is never touched.

### 2. Structured Observability Over Raw Logs

Kilroy has three layers of observability: per-stage file artifacts (prompt, response, diff), run-level structured event logs (append-only NDJSON), and a persistent execution database for history. Raw stdout is captured but never the primary interface — typed events are.

**Citadel application:** The AgentRunEvent resource (P-23) gives us typed, queryable events from the start. The review UI should present structured data (what happened, in what order, what failed) rather than scrollable log dumps.

### 3. Fail Fast, Fail Visibly

Kilroy validates everything before starting work: provider connectivity, model availability, system readiness. During execution, a stall watchdog kills idle runs. Failures are classified (transient vs. deterministic) to decide retry strategy.

**Citadel application:** Preflight checks (P-25) catch misconfigured agents before they waste a task cycle. Stall detection kills hung processes. Every failure should produce a clear, actionable error — not a silent timeout.

### 4. Human Gates Are the Killer Feature

Kilroy allows pipeline nodes that pause and ask the developer a question. This is the mechanism that keeps the human in the loop without requiring constant supervision. The agent works autonomously until it genuinely needs a decision.

**Citadel application:** This maps directly to our "dev lead managing AI workers" vision. An agent that can say "I found two approaches, which do you prefer?" is fundamentally more trustworthy than one that guesses. This should be a core capability, not an afterthought.

### 5. Checkpoints Enable Resilience

Every completed stage in Kilroy produces a checkpoint commit and a state snapshot. Runs can resume from any checkpoint — even on a different machine. This turns long-running, fragile pipelines into resumable, fault-tolerant workflows.

**Citadel application:** Not needed for the PoC (agent runs are short), but essential as tasks become multi-step. Design the execution model so checkpointing can be added without restructuring.

### 6. Model Escalation Saves Money

Kilroy starts with cheaper models and escalates to more capable ones only after failures. This is a simple but effective cost optimization that also tends to produce faster results for easy tasks.

**Citadel application:** Future enhancement, but worth designing for. The agent should accept model configuration, and escalation chains should be configurable per-project.

---

## What to Get Right

These are the capabilities that, if done well, define Citadel's value. Getting them wrong or skipping them undermines the entire product.

### 1. The Agent Loop Must Be Reliable

The core loop — pick up task, execute, report results — must work every time. A developer who assigns a task to an agent and comes back to find it silently failed with no explanation will not use the product again.

This means:
- Preflight validation before accepting work
- Stall detection during execution
- Structured error reporting on failure
- Clean resource cleanup (worktrees, processes) in all exit paths

### 2. The Review Experience Must Be Good

The developer reviews agent output like a tech lead reviews a junior's PR. The review UI is the most important surface in the product. It needs to show:
- What changed (diff)
- Why it changed (the task description and agent's reasoning)
- Whether it works (test results, event log)
- What to do next (approve, reject, request changes)

A bad review experience makes the developer feel like they're debugging the agent instead of leading it.

### 3. Status Must Be Transparent

The developer should always know: Is my agent connected? Is it working? On what? For how long? What happened last? Ambiguity erodes trust. Phoenix Presence gives us real-time connection status. Structured events give us execution status. The UI should surface both prominently.

### 4. The Handoff Must Be Clean

When an agent finishes work, the result should be a clean git branch with atomic commits and a clear diff. Not a branch with 47 work-in-progress commits. Not uncommitted changes in a worktree. The handoff from agent to developer should feel like receiving a well-prepared PR.

---

## Guiding Principles

Reference these when making implementation decisions.

### Agents Are Junior Developers, Not Autonomous Systems

Design every interaction as if you're managing a capable but inexperienced team member. They need clear instructions (task descriptions), a defined workspace (worktree), supervision (status tracking, stall detection), and a review process (approve/reject). They should escalate when uncertain (human gates), not guess.

### Visibility Over Autonomy

When in doubt, surface more information rather than making more decisions automatically. The developer should always understand what the agent did and why. Structured events, clear diffs, and transparent status are more valuable than clever automation that hides its reasoning.

### Fail Loudly, Recover Gracefully

Silent failures are the worst outcome. Every failure path should produce a visible, actionable result — an error event, a failed status, a clear message. But failures should also be recoverable: clean up resources, preserve partial work where possible, and make it easy to retry.

### Local-First Execution, Cloud-First Coordination

Code never leaves the developer's machine. The agent runs locally, works on local files, uses the developer's own AI API keys. Citadel (the cloud service) coordinates — it assigns work, tracks status, stores results, and provides the review UI. This split is fundamental to the trust model and the business model.

### Design for the Single-Agent Case, Architect for Multi-Agent

Every feature should work perfectly with one agent and one task. But the data model and execution model should not preclude multiple agents working in parallel. Worktree isolation, workspace-scoped presence, and per-run event logs all naturally extend to multi-agent without redesign.

### Structured Data Over Unstructured Text

Prefer typed events over log lines. Prefer queryable fields over free-text blobs. Prefer JSON over stdout. Unstructured data is easy to produce and hard to use. Structured data powers the UI, enables filtering, and supports future analytics.

### The Developer's Time Is the Bottleneck

The product exists to multiply developer productivity. Every feature should be evaluated against: does this save the developer time, or does it create more work? A review flow that takes 30 seconds to understand is worth more than an autonomous flow that sometimes produces wrong results the developer has to debug.
