# Test script for GitHub MCP connection via remote HTTP server
# Run with: mix run test_mcp_remote.exs

pat = System.get_env("GITHUB_PAT") || raise "Set GITHUB_PAT environment variable"

IO.puts("Testing GitHub MCP remote server at api.githubcopilot.com...")

# Start a temporary supervisor with the MCP client using HTTP transport
children = [
  {Citadel.MCP.GitHubClient,
   transport:
     {:streamable_http,
      base_url: "https://api.githubcopilot.com",
      mcp_path: "/mcp/",
      headers: %{"Authorization" => "Bearer #{pat}"}}}
]

case Supervisor.start_link(children, strategy: :one_for_one) do
  {:ok, sup_pid} ->
    IO.puts("Supervisor started with PID: #{inspect(sup_pid)}")

    # Give the client time to initialize
    Process.sleep(3000)

    IO.puts("\nTesting ping...")

    case Citadel.MCP.GitHubClient.ping() do
      :pong ->
        IO.puts("✓ Ping successful!")

      error ->
        IO.puts("✗ Ping failed: #{inspect(error)}")
    end

    IO.puts("\nDiscovering tools...")

    case Citadel.MCP.GitHubClient.list_tools() do
      {:ok, %Hermes.MCP.Response{result: %{"tools" => tools}}} ->
        IO.puts("✓ Found #{length(tools)} tools:\n")

        Enum.take(tools, 10)
        |> Enum.each(fn tool ->
          IO.puts("  - #{tool["name"]}")
        end)

        IO.puts("  ... and #{length(tools) - 10} more")

        # Test calling a tool
        IO.puts("\n\nTesting get_me tool...")

        case Citadel.MCP.GitHubClient.call_tool("get_me", %{}) do
          {:ok, result} ->
            IO.puts("✓ get_me succeeded!")
            IO.inspect(result.result, label: "Result", pretty: true)

          {:error, error} ->
            IO.puts("✗ get_me failed: #{inspect(error)}")
        end

      {:ok, other} ->
        IO.puts("Unexpected response format:")
        IO.inspect(other, pretty: true)

      {:error, error} ->
        IO.puts("✗ Failed to list tools: #{inspect(error)}")
    end

    # Stop the supervisor
    Supervisor.stop(sup_pid)
    IO.puts("\n✓ Test completed!")

  {:error, reason} ->
    IO.puts("✗ Failed to start supervisor: #{inspect(reason)}")
end
