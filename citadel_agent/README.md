# CitadelAgent

A local execution agent that polls Citadel for agent-eligible tasks, executes them via the Claude Code CLI in isolated git worktrees, and reports results back.

## Prerequisites

- Elixir ~> 1.19
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and available in `PATH`
- Git
- A running Citadel instance with a valid API key

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `CITADEL_API_KEY` | Yes | — | API key for authenticating with the Citadel API |
| `CITADEL_PROJECT_PATH` | Yes | — | Absolute path to the git repository the agent works against |
| `CITADEL_URL` | No | `http://localhost:4000` | Base URL of the Citadel instance |
| `CITADEL_POLL_INTERVAL` | No | `10000` | How often (in ms) the agent polls for new tasks |
| `CITADEL_STALL_TIMEOUT` | No | `600000` | Max time (in ms) a Claude Code process can run before being killed |

## Getting Started

```bash
# Install dependencies
mix deps.get

# Run preflight checks only (validates CLI tools, project path, and API connectivity)
CITADEL_API_KEY=your_key CITADEL_PROJECT_PATH=/path/to/repo mix citadel_agent.run --preflight-only

# Start the agent
CITADEL_API_KEY=your_key CITADEL_PROJECT_PATH=/path/to/repo mix citadel_agent.run
```

The agent will start polling the Citadel API for tasks. Press `Ctrl+C` to stop.

## How It Works

1. The worker polls `GET /api/agent/tasks/next` on the configured interval
2. When a task is found, it creates an `AgentRun` record via the API
3. A git worktree is created at `<project_path>/.worktrees/task-<human_id>` on a branch named `citadel/task-<human_id>`
4. Claude Code CLI is invoked with the task title and description as a prompt
5. On completion, the diff and logs are reported back to Citadel
6. If successful, the task is transitioned to "In Review"
7. The worktree is cleaned up (branch is kept if it has commits)
