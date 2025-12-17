defmodule Citadel.MCP.GitHubClient do
  @moduledoc """
  MCP client for connecting to GitHub's MCP server.

  Uses hermes_mcp to communicate with GitHub's remote MCP server via HTTP.
  No Docker or Copilot subscription required - just a GitHub PAT.

  ## Usage

  Start in supervision tree:

      children = [
        {Citadel.MCP.GitHubClient,
         transport: {:streamable_http,
           base_url: "https://api.githubcopilot.com",
           mcp_path: "/mcp/",
           headers: %{"Authorization" => "Bearer " <> pat}
         }}
      ]

  Then use the client:

      {:ok, response} = Citadel.MCP.GitHubClient.list_tools()
      {:ok, result} = Citadel.MCP.GitHubClient.call_tool("get_file_contents", %{
        owner: "owner",
        repo: "repo",
        path: "README.md"
      })

  ## Available Tools (40 total)

  Key tools for code inspection:
  - `get_file_contents` - Read files from repositories
  - `search_code` - Search code across repositories
  - `list_commits` - View commit history
  - `get_me` - Get authenticated user info
  """

  use Hermes.Client,
    name: "Citadel",
    version: "0.1.0",
    protocol_version: "2025-03-26"
end
