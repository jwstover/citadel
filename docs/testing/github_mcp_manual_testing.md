# GitHub MCP Integration - Manual Testing Procedures

This document describes manual testing procedures for the GitHub MCP integration. These tests require a real GitHub Personal Access Token (PAT) and cannot be automated in CI.

## Prerequisites

1. A GitHub account
2. A GitHub Personal Access Token (PAT) with appropriate scopes:
   - `repo` (for private repository access)
   - `read:user` (for user info)
3. A running Citadel development server

## Setup

### 1. Generate a GitHub PAT

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Select scopes: `repo`, `read:user`
4. Copy the generated token (starts with `ghp_`)

### 2. Start the Development Server

```bash
iex -S mix phx.server
```

## Test Procedures

### Test 1: Token Validation

**Purpose:** Verify that invalid tokens are rejected before being stored.

**Steps:**
```elixir
# Get your user and workspace
user = Citadel.Accounts.get_user_by_email!("your@email.com")
workspace = Citadel.Accounts.list_workspaces!(actor: user) |> hd()

# Try with an invalid token
Citadel.Integrations.create_github_connection("invalid_token", tenant: workspace.id, actor: user)
```

**Expected Result:**
- Returns `{:error, %Ash.Error.Invalid{}}` with message "Invalid GitHub token"
- No connection is created in the database

### Test 2: Create GitHub Connection

**Purpose:** Verify that a workspace owner can create a GitHub connection with a valid PAT.

**Steps:**
1. Log in as a workspace owner
2. Navigate to workspace settings (or use IEx)
3. Add a GitHub connection with your PAT

**Via IEx:**
```elixir
# Get your user and workspace
user = Citadel.Accounts.get_user_by_email!("your@email.com")
workspace = Citadel.Accounts.list_workspaces!(actor: user) |> hd()

# Create the connection with a valid PAT
pat = "ghp_your_token_here"
Citadel.Integrations.create_github_connection!(pat, tenant: workspace.id, actor: user)
```

**Expected Result:**
- Connection is created successfully
- PAT is encrypted in the database
- `github_username` is populated with your GitHub username

### Test 3: Verify MCP Tools Load

**Purpose:** Verify that GitHub MCP tools are loaded for a workspace with a connection.

**Steps:**
```elixir
# Get the workspace ID
workspace_id = "your-workspace-uuid"

# Try to get tools
Citadel.MCP.ClientManager.get_tools(workspace_id)
```

**Expected Result:**
- `{:ok, tools}` where `tools` is a list of `LangChain.Function` structs
- Tools should include things like `get_file_contents`, `search_code`, etc.
- Check logs for "Loaded X GitHub MCP tools for workspace..."

### Test 4: Chat with GitHub Tools

**Purpose:** Verify that the AI can use GitHub tools in chat conversations.

**Steps:**
1. Start a new chat conversation in the workspace with the GitHub connection
2. Ask a question that requires GitHub access, such as:
   - "Can you search for files containing 'defmodule' in the anthropics/claude-code repository?"
   - "What's in the README.md of anthropics/claude-code?"
   - "Show me recent commits in anthropics/claude-code"

**Expected Result:**
- AI should use the appropriate GitHub tool
- Tool calls should appear in the message's `tool_calls` field
- Tool results should appear in the message's `tool_results` field
- AI should incorporate the results into its response

### Test 5: Chat Without GitHub Connection

**Purpose:** Verify that chat works normally without a GitHub connection (no regression).

**Steps:**
1. Use a workspace without a GitHub connection
2. Start a chat conversation
3. Ask any question

**Expected Result:**
- Chat works normally
- No errors about missing GitHub tools
- System prompt should NOT mention GitHub capabilities

### Test 6: Connection Deletion Cleanup

**Purpose:** Verify that deleting a GitHub connection cleans up the MCP client.

**Steps:**
```elixir
# Get the connection
connection = Citadel.Integrations.get_workspace_github_connection!(workspace_id,
  tenant: workspace_id,
  actor: user
)

# Delete it
Citadel.Integrations.delete_github_connection!(connection, actor: user)

# Verify client is stopped (should return :ok even if not running)
Citadel.MCP.ClientManager.stop_client(workspace_id)

# Try to get tools - should now return :no_connection
Citadel.MCP.ClientManager.get_tools(workspace_id)
```

**Expected Result:**
- Connection is deleted
- `get_tools/1` returns `{:error, :no_connection}`

### Test 7: Error Handling - Invalid PAT (via UI)

**Purpose:** Verify graceful handling of invalid/expired tokens.

**Steps:**
1. Create a connection with an invalid PAT: `ghp_invalid_token_12345`
2. Try to use chat in that workspace

**Expected Result:**
- MCP client fails to connect (logged as warning)
- Chat still works, but without GitHub tools
- No crash or user-visible error

### Test 8: Error Handling - Rate Limiting

**Purpose:** Verify handling of GitHub API rate limits.

**Note:** This is difficult to trigger intentionally. Monitor logs during heavy usage.

**Expected Result:**
- Rate limit errors should be logged
- Chat should continue working (with or without GitHub tools)
- No crashes

## Debugging Tips

### Check MCP Client Status

```elixir
# See if a client is registered for a workspace
Registry.lookup(Citadel.MCP.ClientRegistry, workspace_id)
```

### View Available Tools

```elixir
{:ok, tools} = Citadel.MCP.ClientManager.get_tools(workspace_id)
Enum.map(tools, & &1.name) |> Enum.sort()
```

### Check Logs

Look for these log messages:
- `[debug] Loaded X GitHub MCP tools for workspace...` - Tools loaded successfully
- `[warning] Failed to get MCP tools for workspace...` - Tool loading failed
- `[error] Failed to start MCP client for workspace...` - Client startup failed

### Inspect Message Tool Usage

```elixir
# Get a message with tool calls
message = Citadel.Chat.get_message!(message_id, authorize?: false)
IO.inspect(message.tool_calls, label: "Tool Calls")
IO.inspect(message.tool_results, label: "Tool Results")
```

## Known Limitations

1. **No OAuth flow:** Currently only supports PAT authentication, not GitHub OAuth
2. **No tool filtering:** All 40+ GitHub MCP tools are exposed; may want to limit to read-only tools
3. **Single connection per workspace:** Cannot connect multiple GitHub accounts
4. **No token refresh:** PATs don't expire, but if revoked, connection must be recreated
