# Pyllar - AI Project Manager for Claude Code

> "AI that does, not just suggests" - Proactive project management that keeps your tasks in sync with reality.

## Overview

Pyllar transforms Claude into a proactive AI project manager. It provides intelligent task management that automatically tracks your work, identifies blockers, and keeps your task board in sync with what's actually happening in your codebase.

## Features

- **Smart Task Breakdown**: Describe a feature, get actionable subtasks with dependencies
- **Proactive Analysis**: Automatic blocker and bottleneck detection at session start
- **Daily Standups**: Generate standup summaries instantly
- **Workload Balancing**: Capacity analysis and rebalancing suggestions
- **Auto State Management**: Tasks automatically move to "In Progress" when you start and "Complete" when you finish
- **Learning Memory**: Improves recommendations based on your team's patterns

## Installation

```bash
claude plugin add pyllar
```

## Configuration

Pyllar connects to your backend via the Model Context Protocol (MCP). You'll need to configure the MCP server connection.

### Quick Setup

1. Copy the MCP configuration template:
   ```bash
   cp .mcp.json.template .mcp.json
   ```

2. Set your environment variables:
   ```bash
   # Required: Your Pyllar/Citadel MCP endpoint
   export PYLLAR_MCP_URL="https://your-pyllar-instance.com/mcp"

   # Required for authenticated endpoints
   export PYLLAR_API_KEY="your-api-key"
   ```

### Development Setup

For local development with Citadel running on localhost:

```bash
export PYLLAR_MCP_URL="http://localhost:4110/tidewave/mcp"
# API key may not be required for local development
```

Alternatively, edit `.mcp.json` directly with your development URL:
```json
{
  "mcpServers": {
    "pyllar": {
      "type": "http",
      "url": "http://localhost:4110/tidewave/mcp"
    }
  }
}
```

### Production Setup

For production use:

1. Obtain your API key from your Pyllar instance
2. Set both environment variables:
   ```bash
   export PYLLAR_MCP_URL="https://your-instance.pyllar.dev/mcp"
   export PYLLAR_API_KEY="pyllar_xxxxxxxxxxxx"
   ```

### Authentication

Pyllar currently supports API key authentication via Bearer tokens. The API key is passed in the `Authorization` header of all MCP requests.

**Future Enhancement**: OAuth authentication is planned for a future release to enable more secure, user-scoped access.

## Quick Start

### Start working on a task
```
/pyllar:work-on PYL-123
```
Automatically sets the task to "In Progress" and loads context.

### Break down a feature
```
/pyllar:breakdown "Add user authentication with OAuth"
```
Creates a parent task with hierarchical subtasks.

### Generate a standup
```
/pyllar:standup
```
Shows what's done, in progress, and blocked.

### Groom the backlog
```
/pyllar:backlog
```
Identifies stale tasks, missing priorities, and suggests cleanup.

## Commands

| Command | Description |
|---------|-------------|
| `/pyllar:work-on <task-id>` | Start working on a task (auto In Progress) |
| `/pyllar:plan <description>` | Interactively plan and create a task |

## Skills

| Skill | Description |
|-------|-------------|
| `/pyllar:breakdown <feature>` | Break down a feature into subtasks |
| `/pyllar:standup [since-date]` | Generate daily standup summary |
| `/pyllar:backlog` | Analyze and groom the backlog |

## Agents

### Project Analyst
Proactively identifies blocked tasks, stale work, and bottlenecks. Runs automatically at session start.

### Capacity Planner
Analyzes workload distribution and suggests rebalancing for teams. For solo devs, helps manage WIP limits.

## How Auto State Management Works

1. When you run `/pyllar:work-on PYL-123`, the task automatically moves to "In Progress"
2. As you work, Claude tracks your progress
3. When work is complete (tests pass, you confirm), the task moves to "Complete"
4. If you hit a blocker, it's documented in the task and the task stays "In Progress"

## License

MIT
