# Agent Design Principles

Insights and guiding principles for Citadel's agent execution model, informed by research into [Kilroy](https://github.com/danshapiro/kilroy), [StrongDM Factory](https://factory.strongdm.ai/), and the emerging patterns in AI-assisted software development.

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

## Key Learnings from StrongDM Factory

StrongDM Factory is an agentic development platform that pursues fully autonomous, non-interactive development — agents write code, validate it, and ship it without human review. Their position is more aggressive than Citadel's, but several of their techniques and insights are directly applicable.

### 1. Scenario-Based Validation Over Boolean Tests

StrongDM replaces traditional pass/fail test suites with end-to-end "scenarios" (user stories stored outside codebases) and a probabilistic "satisfaction" metric — what fraction of observed user trajectories through the scenario would satisfy a real user. This is more resilient than brittle assertions when agents are generating code.

**Citadel application:** Agents that can self-validate against scenarios before presenting work to the developer produce better results and reduce review burden. As we build validation infrastructure, think in terms of "does this satisfy the user's intent?" not just "do the tests pass?"

### 2. Digital Twin Universe (DTU)

StrongDM clones the externally observable behavior of third-party services (Okta, Jira, Slack, Google Docs) to enable testing at volumes and rates far exceeding production limits. This also allows testing failure modes impossible against live services.

**Citadel application:** As agents interact with external services and APIs, having behavioral clones of dependencies enables reliable, repeatable validation. Worth keeping in mind as the platform matures.

### 3. Shift Work — Separating Intent from Execution

StrongDM cleanly separates interactive development (spec writing, intent clarification) from fully-specified execution. Once the specification is complete, the agent runs end-to-end without human back-and-forth.

**Citadel application:** The quality of the task description is the boundary between human and agent work. A well-specified task should be everything an agent needs. This reinforces investing in good task structure and making it easy for developers to provide complete specifications upfront.

### 4. The Filesystem as Agent Memory

Rather than complex memory systems, StrongDM's agents use the repository filesystem itself as working memory — reading and writing files for state management. Simple, auditable, and version-controlled.

**Citadel application:** The worktree *is* the agent's memory. This aligns with our isolation model and means agent state is naturally captured in git history. No need for separate state stores during execution.

### 5. Validate Behavior, Not Structure

StrongDM treats generated code as opaque — like ML model weights — and validates exclusively through externally observable behavior, never by inspecting source code structure.

**Citadel application:** Agent work should be validated by running tests and checking behavior, not by having another model review the code. Invest in automated validation that proves the work is correct, rather than structural analysis of the output.

### 6. Weather Reports for Model Performance

Instead of traditional metrics dashboards, StrongDM publishes narrative "Weather Reports" tracking which models perform best for which task categories, with configuration parameters and performance notes across 13+ task types.

**Citadel application:** As Citadel supports multiple AI providers and models, tracking model performance per task type will inform model escalation chains and default recommendations. The structured data we already capture in AgentRunEvents can power this.

---

## The Autonomy Spectrum

Citadel's long-term trajectory is to progressively reduce mandatory human intervention as validation infrastructure matures. This is not a binary choice between "human reviews everything" and "no humans needed" — it's a spectrum that the developer controls.

### The Progression

**Stage 1: Human-in-the-Loop (current target)**
Agent does work, human reviews everything. This is where trust gets established. The review UI is the primary surface.

**Stage 2: Human-at-the-Gates**
Agent does work, automated validation catches most issues, human only reviews what fails validation or exceeds a confidence threshold. Human Gates become the exception, not the rule.

**Stage 3: Human-Sets-the-Harness**
Human writes the scenarios and validation criteria. Agent writes code, validates it, and ships it. Human only intervenes when satisfaction metrics drop. The developer's role shifts from *reviewer* to *specification writer and validation architect*.

### The Principle

**Invest in validation infrastructure so that human review becomes optional, not mandatory.** Better scenarios, better test harnesses, better behavioral validation — these are the building blocks that let agents earn increasing autonomy. A senior dev lead doesn't review every line of a trusted team member's code. They set standards, define acceptance criteria, and review strategically.

### Design Implications

Every feature we build should be evaluated against: **does this move us toward optional human review, or does it entrench mandatory review?** Look for opportunities to:

- Build automated validation hooks that agents can run before requesting review
- Capture validation results as structured data alongside the work output
- Let developers configure confidence thresholds that determine when review is required
- Track agent success rates per task type to inform trust calibration
- Design the task specification format to be rich enough for autonomous execution

The goal is not to remove the developer — it's to shift their contribution from low-value review to high-value specification and validation design.

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

### 2. The Review Experience Must Be Good (Today), Optional (Tomorrow)

The developer reviews agent output like a tech lead reviews a junior's PR. The review UI is the most important surface in the product *today*. It needs to show:
- What changed (diff)
- Why it changed (the task description and agent's reasoning)
- Whether it works (test results, validation results, event log)
- What to do next (approve, reject, request changes)

A bad review experience makes the developer feel like they're debugging the agent instead of leading it.

However, review is a starting point, not an end state. As validation infrastructure matures, the review UI should progressively become a *spot-check* surface rather than a *mandatory gate*. Design it so that automated validation results are front-and-center — when all scenarios pass and confidence is high, the developer should be able to approve with a glance or configure auto-merge.

### 3. Status Must Be Transparent

The developer should always know: Is my agent connected? Is it working? On what? For how long? What happened last? Ambiguity erodes trust. Phoenix Presence gives us real-time connection status. Structured events give us execution status. The UI should surface both prominently.

### 4. The Handoff Must Be Clean

When an agent finishes work, the result should be a clean git branch with atomic commits and a clear diff. Not a branch with 47 work-in-progress commits. Not uncommitted changes in a worktree. The handoff from agent to developer should feel like receiving a well-prepared PR.

---

## Guiding Principles

Reference these when making implementation decisions.

### Agents Are Junior Developers Growing Into Senior Ones

Design every interaction as if you're managing a capable but inexperienced team member — today. They need clear instructions (task descriptions), a defined workspace (worktree), supervision (status tracking, stall detection), and a review process (approve/reject). They should escalate when uncertain (human gates), not guess.

But the system should also be designed so agents can *earn* autonomy over time. As validation infrastructure improves and agent success rates climb, the developer should be able to grant increasing trust — fewer mandatory reviews, higher confidence thresholds for escalation, and eventually fully autonomous execution within well-validated domains.

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

The highest-leverage use of developer time is writing good specifications and building validation harnesses — not reviewing generated code line by line. As the platform matures, shift the developer's contribution upstream (intent, acceptance criteria) rather than downstream (code review).

### Validation Is the Path to Autonomy

Every investment in automated validation infrastructure — scenario harnesses, behavioral testing, confidence metrics — is an investment in reducing mandatory human oversight. When building any feature, ask: "does this make it possible for an agent to prove its own work is correct?" If yes, it's a step toward optional review. If no, it entrenches the bottleneck.
