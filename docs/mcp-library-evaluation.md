# MCP Library Evaluation (PER-31 & PER-32)

## Summary

**Recommendation: Use `hermes_mcp ~> 0.14` for GitHub MCP integration.**

`langchain_mcp` has compatibility issues with its dependency `anubis_mcp 0.16.0`, while `hermes_mcp` works reliably out of the box.

---

## Test Results

### langchain_mcp ~> 0.2.0

| Aspect | Result |
|--------|--------|
| **Installation** | ✓ Compiles successfully |
| **Connection** | ✗ Failed - compatibility issue |
| **Tool Discovery** | ✗ Not tested (connection failed) |
| **Tool Execution** | ✗ Not tested |

**Issue Found:** `langchain_mcp 0.2.0` calls `Adapter.wait_for_server_ready/2` which internally sends a `:which_children` message to the Anubis client. However, `anubis_mcp 0.16.0` doesn't handle this message, causing a `FunctionClauseError`:

```
** (FunctionClauseError) no function clause matching in Anubis.Client.Base.handle_call/3
    (anubis_mcp 0.16.0) lib/anubis/client/base.ex:825: Anubis.Client.Base.handle_call(:which_children, ...)
```

This is a version incompatibility that would need to be fixed upstream.

---

### hermes_mcp ~> 0.14.1

| Aspect | Result |
|--------|--------|
| **Installation** | ✓ Compiles successfully |
| **Connection** | ✓ Connects via Docker STDIO transport |
| **Tool Discovery** | ✓ Found 40 GitHub tools |
| **Tool Execution** | ✓ `get_me` tool returned user data |

**Test Output:**
```
✓ Ping successful!
✓ Found 40 tools
✓ get_me succeeded!
```

**Available GitHub Tools (40 total):**
- Repository: `get_file_contents`, `search_code`, `create_branch`, `push_files`, `fork_repository`
- Issues: `issue_read`, `issue_write`, `list_issues`, `search_issues`, `add_issue_comment`
- Pull Requests: `pull_request_read`, `create_pull_request`, `merge_pull_request`, `list_pull_requests`
- Users: `get_me`, `search_users`, `get_team_members`
- And many more...

---

## GitHub MCP Authentication (PER-32)

### PAT Authentication - Works

**Required PAT Scopes (Fine-grained token):**
- `Contents: Read-only` - For reading repository files
- `Metadata: Read-only` - For basic repository info

### Remote HTTP Server (Recommended for Production)

**No Docker or Copilot subscription required!**

```elixir
{Citadel.MCP.GitHubClient,
 transport: {:streamable_http,
   base_url: "https://api.githubcopilot.com",
   mcp_path: "/mcp/",
   headers: %{"Authorization" => "Bearer #{pat}"}
 }}
```

- **Protocol:** MCP 2025-03-26 (required for remote server)
- **Transport:** Streamable HTTP

### Docker Alternative (for local development/testing)

```elixir
{Citadel.MCP.GitHubClient,
 transport: {:stdio,
   command: "docker",
   args: ["run", "-i", "--rm",
          "-e", "GITHUB_PERSONAL_ACCESS_TOKEN=#{pat}",
          "ghcr.io/github/github-mcp-server"]
 }}
```

- **Protocol:** MCP 2024-11-05
- **Docker Image:** `ghcr.io/github/github-mcp-server:latest`

### Copilot Subscription

**Not required** for PAT-based authentication. The remote server at `api.githubcopilot.com` accepts standard GitHub PATs.

---

## Comparison Matrix

| Feature | langchain_mcp | hermes_mcp |
|---------|---------------|------------|
| **Stability** | Issues with anubis 0.16 | Stable |
| **Downloads** | 61 all-time | 19,432 all-time |
| **LangChain Integration** | Built-in `Adapter.to_functions/1` | Manual conversion needed |
| **Maintenance** | Single maintainer | CloudWalk team |
| **Documentation** | Limited | Comprehensive |
| **Protocol Versions** | 2025-03-26 | 2024-11-05, 2025-03-26 |

---

## LangChain Integration Path

Since we're using `hermes_mcp`, we need to manually convert MCP tools to LangChain functions. Here's the pattern:

```elixir
defmodule Citadel.MCP.LangChainAdapter do
  @moduledoc "Converts hermes_mcp tools to LangChain functions"

  alias LangChain.Function

  def to_langchain_functions(tools) when is_list(tools) do
    Enum.map(tools, &to_langchain_function/1)
  end

  defp to_langchain_function(%{"name" => name, "description" => desc, "inputSchema" => schema}) do
    Function.new!(%{
      name: name,
      description: desc,
      parameters_schema: convert_schema(schema),
      function: fn args, _context ->
        case Citadel.MCP.GitHubClientHermes.call_tool(name, args) do
          {:ok, %{result: %{"content" => [%{"text" => text}]}}} -> text
          {:error, error} -> "Error: #{inspect(error)}"
        end
      end
    })
  end

  defp convert_schema(%{"properties" => props, "required" => required}) do
    %{
      type: "object",
      properties: convert_properties(props),
      required: required
    }
  end

  defp convert_properties(props) do
    Map.new(props, fn {key, value} ->
      {key, %{type: value["type"], description: value["description"]}}
    end)
  end
end
```

---

## Rate Limits

GitHub API rate limits apply:
- **Authenticated (PAT):** 5,000 requests/hour
- Rate limit headers returned: `X-RateLimit-Remaining`, `X-RateLimit-Reset`

---

## Next Steps

1. **Remove langchain_mcp** from dependencies (not needed)
2. **Keep hermes_mcp** as the MCP client
3. **Implement LangChain adapter** to convert hermes tools to LangChain functions
4. **Add to Respond change** to inject GitHub tools when workspace has connection
5. **Create GitHubConnection resource** to store encrypted PAT per workspace

---

## Files Created During Research

- `lib/citadel/mcp/github_client.ex` - hermes_mcp client (working)
- `test_mcp_hermes.exs` - Test script for GitHub MCP connection

**Removed (not needed):**
- langchain_mcp dependency removed from mix.exs
- anubis_mcp (transitive dependency) removed
