defmodule Citadel.MCP.ClientManagerTest do
  use Citadel.DataCase, async: true

  alias Citadel.Integrations
  alias Citadel.MCP.ClientManager

  describe "get_tools/1" do
    test "returns error for nil workspace_id" do
      assert ClientManager.get_tools(nil) == {:error, :no_workspace}
    end

    test "returns error when workspace has no GitHub connection" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      assert {:error, :no_connection} = ClientManager.get_tools(workspace.id)
    end
  end

  describe "stop_client/1" do
    test "returns :ok for nil" do
      assert ClientManager.stop_client(nil) == :ok
    end

    test "returns :ok for non-existent client" do
      fake_workspace_id = Ash.UUID.generate()
      assert ClientManager.stop_client(fake_workspace_id) == :ok
    end
  end

  describe "integration with GitHubConnection" do
    test "workspace with connection but MCP server unavailable returns error" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      pat = "ghp_fake_token_#{System.unique_integer([:positive])}"

      Integrations.create_github_connection!(pat,
        tenant: workspace.id,
        actor: owner
      )

      result = ClientManager.get_tools(workspace.id)

      assert match?({:error, _reason}, result)
    end
  end
end
