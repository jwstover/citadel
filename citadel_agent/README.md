# CitadelAgent

A local execution agent that polls Citadel for agent-eligible tasks, executes them via the Claude Code CLI in isolated git worktrees, and reports results back.

## Install

The shipped artifact is a self-contained Erlang/OTP release tarball. Releases are built per `(os, arch)` pair — pick the one that matches your machine.

```bash
# Pick the right tarball for your platform from the latest release.
TARBALL="citadel-agent-0.1.0-darwin-arm64.tar.gz"

curl -LO "https://github.com/jwstover/citadel/releases/latest/download/${TARBALL}"
tar xzf "${TARBALL}"
# Optional: move it somewhere on PATH
sudo mv citadel_agent /usr/local/lib/citadel_agent
sudo ln -s /usr/local/lib/citadel_agent/bin/citadel_agent /usr/local/bin/citadel_agent
```

## Prerequisites on PATH

- [`claude`](https://docs.anthropic.com/en/docs/claude-code) — Claude Code CLI, authenticated via `claude auth login` (SSO).
- `git`
- `gh` is optional but recommended; the agent uses the GitHub REST API directly via `GITHUB_TOKEN`.

The agent will not start if any prerequisite is missing or if `claude` is not authenticated. Run a preflight check first:

```bash
CITADEL_API_KEY=… CITADEL_PROJECT_PATH=… GITHUB_TOKEN=… \
  citadel_agent eval 'CitadelAgent.Preflight.run!()'
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `CITADEL_API_KEY` | Yes | — | API key for authenticating with the Citadel API |
| `CITADEL_PROJECT_PATH` | Yes | — | Absolute path to the git repository the agent works against |
| `GITHUB_TOKEN` | Yes | — | GitHub PAT used for branch pushes and PR creation |
| `CITADEL_URL` | No | Citadel public URL | Base URL of the Citadel instance |
| `CITADEL_POLL_INTERVAL` | No | `10000` | How often (in ms) the agent polls for new tasks |
| `CITADEL_STALL_TIMEOUT` | No | `600000` | Max time (in ms) a Claude Code process can run before being killed |
| `CITADEL_AGENT_NAME` | No | hostname | Display name for this agent in the Citadel UI |

## Run

```bash
# Foreground (recommended; logs to stdout, Ctrl+C to stop)
CITADEL_API_KEY=… CITADEL_PROJECT_PATH=… GITHUB_TOKEN=… \
  citadel_agent start

# Backgrounded
citadel_agent daemon

# Stop a backgrounded agent
citadel_agent stop
```

Preflight runs automatically on every boot. If anything is misconfigured, the binary exits with a clear error before any work begins.

## Building from Source

If you want to build a tarball yourself (e.g. to ship a Linux build from a Linux host):

```bash
mix deps.get
scripts/package.sh
# → dist/citadel-agent-<version>-<os>-<arch>.tar.gz
```

BEAM releases are not portable across `(os, arch)` pairs. To produce a darwin-arm64 build you must run the script on a darwin-arm64 host; same for darwin-x86_64, linux-x86_64, and linux-arm64.

## Development

For local development against a Citadel running on `http://localhost:4100`:

```bash
mix deps.get
CITADEL_DEV_API_KEY=… GITHUB_TOKEN=… mix citadel_agent.run
```

Use `--preflight-only` to validate the environment without entering the poll loop.

## How It Works

1. The worker polls `GET /api/agent/tasks/next` on the configured interval.
2. When a task is found, it creates an `AgentRun` record via the API.
3. A git worktree is created at `<project_path>/.worktrees/task-<human_id>` on a branch named `citadel/task-<human_id>`.
4. The Claude Code CLI is invoked with the task title and description as a prompt.
5. On completion, the diff and structured event log are reported back to Citadel.
6. If successful, the task is transitioned to "In Review" and a draft PR is opened.
7. The worktree is cleaned up (branch is kept if it has commits).
