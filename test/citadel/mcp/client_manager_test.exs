defmodule Citadel.MCP.ClientManagerTest do
  use Citadel.DataCase, async: true

  alias Citadel.Accounts
  alias Citadel.Integrations
  alias Citadel.MCP.ClientManager

  describe "get_tools/1" do
    test "returns error for nil workspace_id" do
      assert ClientManager.get_tools(nil) == {:error, :no_workspace}
    end

    test "returns error when workspace has no GitHub connection" do
      owner = create_user()

      workspace =
        Accounts.create_workspace!("Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      assert {:error, :no_connection} = ClientManager.get_tools(workspace.id)
    end

    # Note: Testing with an actual GitHub connection requires either:
    # 1. A real GitHub PAT (not suitable for automated tests)
    # 2. Mocking the MCP client at the HTTP level
    # See docs/testing/github_mcp_manual_testing.md for manual testing procedures
  end

  describe "stop_client/1" do
    test "returns :ok for nil" do
      assert ClientManager.stop_client(nil) == :ok
    end

    test "returns :ok for non-existent client" do
      # Random UUID that doesn't have a running client
      fake_workspace_id = Ash.UUID.generate()
      assert ClientManager.stop_client(fake_workspace_id) == :ok
    end
  end

  describe "integration with GitHubConnection" do
    test "workspace with connection but MCP server unavailable returns error" do
      # This test verifies the error handling when the MCP connection fails
      # In CI/test environments, the GitHub MCP server won't be reachable
      owner = create_user()

      workspace =
        Accounts.create_workspace!("Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      # Create a connection with a fake PAT
      pat = "ghp_fake_token_#{System.unique_integer([:positive])}"

      Integrations.create_github_connection!(pat,
        tenant: workspace.id,
        actor: owner
      )

      # The client will try to connect to GitHub's MCP server and fail
      # This tests our error handling path
      result = ClientManager.get_tools(workspace.id)

      # Should return an error (connection refused, timeout, etc.)
      # The specific error depends on network conditions
      assert match?({:error, _reason}, result)
    end
  end
end
