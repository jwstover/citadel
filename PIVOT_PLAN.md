# Citadel Pivot Plan: AI Development Platform

## Vision

Citadel evolves from a task management app into an **AI development platform** where developers act as dev leads overseeing a team of AI agents that plan, implement, test, and validate code.

The product is not "describe a project and AI builds it." It's a tool that facilitates the emerging workflow where every developer is a dev lead managing AI workers.

---

## Decisions Made

### 1. Execution Environment: Local Docker Agent

**Decision:** Agents run locally on the developer's machine via a Docker image, not server-side on Fly.io.

**Rationale:**
- Code never leaves the developer's machine (solves trust/security)
- No compute costs for Citadel — user provides their own machine
- Native access to the developer's actual environment (dependencies, databases, services)
- No need to replicate dev environments on the server side
- FLAME on Fly.io was considered and rejected due to cost, security, and environment replication concerns

### 2. Architecture: Control Plane / Execution Plane Split

**Decision:** Citadel (deployed on Fly.io) is the **control plane**. Local Docker agents are the **execution plane**.

```
┌─────────────────────────┐         ┌──────────────────────┐
│   Citadel (Fly.io)      │         │  Local Docker Agent  │
│                         │         │                      │
│  - Task queue           │◄───────►│  - Git client        │
│  - Planning UI          │  WebSocket  - AI SDK (Claude)  │
│  - Review/approval UI   │         │  - Test runner       │
│  - Agent observability  │         │  - Shell access      │
│  - Workspace/project    │         │  - File system access│
│    management           │         │                      │
│                         │         │  Mounts: ~/projects/ │
└─────────────────────────┘         └──────────────────────┘
```

**Citadel handles:** Planning, task management, review, approval workflows, observability, collaboration.

**Docker agent handles:** Pulling tasks, calling AI APIs, applying code changes, running tests, reporting results.

### 3. AI API Keys: Bring Your Own Key

**Decision:** Users provide their own AI provider API keys, configured in the Docker agent's environment.

**Rationale:**
- Eliminates AI compute costs for Citadel
- Developers expect this model
- Users can choose their preferred provider/model
- Removes a massive cost variable from the business

### 4. Agent Design: Elixir Wrapper around Claude Code

**Decision:** The agent is a thin Elixir application that orchestrates work by shelling out to Claude Code CLI for actual code execution. It does NOT reimplement AI tool use.

**Components:**
- **Elixir app** — Handles Citadel communication, task lifecycle, git operations, and orchestration
- **Claude Code CLI** — The actual execution engine. Receives a task prompt, works on the codebase, produces changes.
- **Claude Code hooks/skills (future)** — Progress reporting and observability will be implemented via Claude Code's hook and skill system, allowing the agent to report status back to Citadel during execution rather than only at completion.

**Rationale:**
- Elixir keeps the agent in the same ecosystem as Citadel (shared knowledge, potential shared code)
- Claude Code already handles file editing, test running, context gathering — no need to reimplement
- Hooks/skills provide a natural extension point for reporting without custom tool-use plumbing
- The agent stays thin: its job is orchestration, not execution
- Users mount their project directory; Claude Code works with whatever's there

**Agent execution flow:**
```
Elixir Agent                          Claude Code CLI
    │                                      │
    │  1. Get task from Citadel            │
    │  2. git checkout -b branch           │
    │  3. Construct prompt from task        │
    │                                      │
    │  System.cmd("claude", [              │
    │    "--task", prompt,                 │
    │    "--allowedTools", ...             │
    │  ])                                  │
    │─────────────────────────────────────►│
    │                                      │  Claude Code does the work:
    │                                      │  - reads files
    │                                      │  - edits code
    │                                      │  - runs tests
    │◄─────────────────────────────────────│
    │                                      │
    │  4. Capture exit code + output        │
    │  5. git diff > results               │
    │  6. POST results to Citadel          │
    │                                      │
```

### 5. Existing Foundations Carry Forward

**Decision:** Don't rip out existing Citadel features. Workspaces, tasks, chat, and background jobs are foundations for the new direction.

**Evolution mapping:**
- Tasks → agent-assignable work units (add agent assignment, execution status, logs)
- Chat → command channel for directing agents on specific tasks
- Workspaces → projects tied to repositories

---

## Architecture Decisions Still Open

### Communication Protocol — DECIDED
**Decision:** Hybrid WebSocket + REST.

- **WebSocket (Phoenix Channels + Presence)** for agent connection lifecycle and status tracking. The agent connects via `slipstream`, joins an `agents:workspace_id` channel, and Presence tracks online/offline/idle/working status automatically. No heartbeat polling or database writes needed for status.
- **REST API** for task pickup (`GET /api/agent/tasks/next`), result reporting (`POST /api/agent/tasks/:id/runs`), and event logging (`POST /api/agent/runs/:id/events`). These are stateless request/response operations that don't benefit from persistent connections.
- Future: task assignment could move to channel push (server assigns work to agent via WebSocket instead of agent polling), but polling is fine for PoC.

### Agent Execution Loop (Proposed)
1. Agent starts, authenticates with Citadel via API token
2. Connects via WebSocket, subscribes to task assignments
3. Picks up a task (e.g., "Implement the user profile endpoint")
4. Creates an isolated git worktree for the task branch (keeps main working tree clean)
5. Calls AI with repo context + task description + project conventions
6. AI produces changes in the worktree
7. Runs tests locally
8. Reports structured results back to Citadel (diff, test output, typed event log)
9. Creates PR or waits for human approval
10. Cleans up worktree, loops back

### Unit of Work
- What exactly does an agent work on? A task? A subtask? A PR?
- Too granular = micromanagement. Too coarse = loss of oversight.
- Needs further discussion.

### Multi-Agent Parallelism
- Start with single-agent, single-task and make that workflow excellent
- Multi-agent comes later once the core loop is proven

---

## Implementation Phases

### Phase 1: Proof of Concept

**Citadel side (API):**
- `POST /api/agent/auth` — Exchange credentials for a session token
- `GET /api/agent/next-task` — Return the next task assigned to an agent for a given project
- `POST /api/agent/tasks/:id/result` — Accept results (status, diff, test output, logs)
- `POST /api/agent/tasks/:id/events` — Accept structured execution events (see Structured Event Log below)
- API token authentication

**Agent side (Elixir app, separate Mix project):**
- Authenticate with Citadel
- Poll for next task
- **Preflight check** — Verify Claude Code CLI is available and API key is valid before accepting work
- Create isolated git worktree: `git worktree add .worktrees/task-{id} -b citadel/task-{id}`
- Construct prompt from task title + description + any context
- Shell out to `claude --task <prompt>` against the worktree directory
- Capture exit code and output
- `git diff` to capture changes
- POST results back to Citadel
- **Stall detection** — Monitor agent idle time; kill and report failure if no progress for configurable timeout (default 10 min)
- Clean up worktree on completion/failure
- Loop

**Structured Event Log (MVP):**
Agent reports typed events to Citadel during and after execution, stored as an append-only log per agent run:
- `run_started` — Agent picked up the task
- `run_completed` / `run_failed` — Terminal states with exit code
- `stage_started` / `stage_completed` — For multi-step tasks (future), but even in PoC, marks "agent working" vs "agent done"
- `error` — Capture failures with context

This replaces raw log dumps with queryable, structured data that powers the review UI.

**Citadel UI:**
- Show task execution status (pending → in_progress → completed/failed)
- Display the diff and structured event log returned by the agent
- Basic approve/reject flow

**Not in scope for PoC:**
- Docker packaging (run the Elixir agent directly first)
- WebSockets (polling is fine)
- Hooks/skills for progress reporting
- Multi-agent
- Planning/decomposition
- Checkpoint/resume (agent runs are short enough to restart)

### Phase 2: Reframe Existing Features
- Add project concept (linked to git repositories)
- Tasks gain agent assignment, execution status, agent logs
- Agent status tracking (online, working on, idle)

### Phase 3: Repository Integration
- GitHub/GitLab connection per project
- Agents work on branches, create PRs
- Code context available to planning and execution layers

### Phase 4: Planning Workflow
- AI-assisted decomposition: describe a feature → AI breaks into subtasks with dependencies
- Dependency graph visualization
- Parallel execution where the graph allows

### Phase 5: Validation Pipeline
- Automated test runs against agent output
- CI integration
- Quality gates before human review

---

## Competitive Positioning

| Tool | Approach | Citadel's Difference |
|------|----------|---------------------|
| Cursor / Claude Code | Single-agent, single-session | Citadel orchestrates multiple agents across workstreams |
| Devin / Factory | Autonomous agent does everything | Citadel keeps the developer in the lead role |
| Linear / Jira + AI | PM tools with AI bolted on | Citadel is agent-native from the ground up |

**The moat is the workflow, not the AI.** Anyone can call Claude's API. The value is making "dev lead managing AI workers" feel natural, trustworthy, and productive.
