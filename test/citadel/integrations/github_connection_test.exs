defmodule Citadel.Integrations.GitHubConnectionTest do
  use Citadel.DataCase, async: true

  require Ash.Query

  alias Citadel.Accounts
  alias Citadel.Integrations
  alias Citadel.Integrations.GitHubConnection

  describe "create_github_connection/2" do
    test "workspace owner can create a GitHub connection" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"

      connection =
        Integrations.create_github_connection!(pat,
          tenant: workspace.id,
          actor: owner
        )

      assert connection.workspace_id == workspace.id
      assert connection.pat_encrypted != nil
    end

    test "encrypts the PAT and can decrypt it" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"

      connection =
        Integrations.create_github_connection!(pat,
          tenant: workspace.id,
          actor: owner
        )

      assert connection.pat_encrypted == pat
    end

    test "non-owner cannot create a GitHub connection" do
      owner = generate(user())
      non_owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"

      assert_raise Ash.Error.Forbidden, fn ->
        Integrations.create_github_connection!(pat,
          tenant: workspace.id,
          actor: non_owner
        )
      end
    end

    test "workspace member (non-owner) cannot create a GitHub connection" do
      owner = generate(user())
      org = generate(organization([], actor: owner))
      upgrade_to_pro(org)
      member = generate(user())
      workspace = generate(workspace([organization_id: org.id], actor: owner))

      Accounts.add_organization_member!(org.id, member.id, :member, actor: owner)
      Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"

      assert_raise Ash.Error.Forbidden, fn ->
        Integrations.create_github_connection!(pat,
          tenant: workspace.id,
          actor: member
        )
      end
    end

    test "only one connection per workspace is allowed" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      pat1 = "ghp_test_token_#{System.unique_integer([:positive])}"
      pat2 = "ghp_test_token_#{System.unique_integer([:positive])}"

      Integrations.create_github_connection!(pat1,
        tenant: workspace.id,
        actor: owner
      )

      assert_raise Ash.Error.Invalid, fn ->
        Integrations.create_github_connection!(pat2,
          tenant: workspace.id,
          actor: owner
        )
      end
    end
  end

  describe "get_workspace_github_connection/1" do
    test "workspace owner can read the connection" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"

      created =
        Integrations.create_github_connection!(pat,
          tenant: workspace.id,
          actor: owner
        )

      connection =
        Integrations.get_workspace_github_connection!(workspace.id,
          tenant: workspace.id,
          actor: owner
        )

      assert connection.id == created.id
      assert connection.pat_encrypted == pat
    end

    test "workspace member can read the connection" do
      owner = generate(user())
      org = generate(organization([], actor: owner))
      upgrade_to_pro(org)
      member = generate(user())
      workspace = generate(workspace([organization_id: org.id], actor: owner))

      Accounts.add_organization_member!(org.id, member.id, :member, actor: owner)
      Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"

      created =
        Integrations.create_github_connection!(pat,
          tenant: workspace.id,
          actor: owner
        )

      connection =
        Integrations.get_workspace_github_connection!(workspace.id,
          tenant: workspace.id,
          actor: member
        )

      assert connection.id == created.id
    end

    test "non-member cannot see the connection (filtered out)" do
      owner = generate(user())
      non_member = generate(user())
      workspace = generate(workspace([], actor: owner))

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"

      Integrations.create_github_connection!(pat,
        tenant: workspace.id,
        actor: owner
      )

      result =
        Integrations.get_workspace_github_connection(workspace.id,
          tenant: workspace.id,
          actor: non_member,
          not_found_error?: false
        )

      assert result == {:ok, nil}
    end

    test "returns nil when no connection exists" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      result =
        Integrations.get_workspace_github_connection(workspace.id,
          tenant: workspace.id,
          actor: owner,
          not_found_error?: false
        )

      assert result == {:ok, nil}
    end
  end

  describe "delete_github_connection/1" do
    test "workspace owner can delete the connection" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"

      connection =
        Integrations.create_github_connection!(pat,
          tenant: workspace.id,
          actor: owner
        )

      assert :ok = Integrations.delete_github_connection!(connection, actor: owner)

      result =
        Integrations.get_workspace_github_connection(workspace.id,
          tenant: workspace.id,
          actor: owner,
          not_found_error?: false
        )

      assert result == {:ok, nil}
    end

    test "workspace member cannot delete the connection" do
      owner = generate(user())
      org = generate(organization([], actor: owner))
      upgrade_to_pro(org)
      member = generate(user())
      workspace = generate(workspace([organization_id: org.id], actor: owner))

      Accounts.add_organization_member!(org.id, member.id, :member, actor: owner)
      Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"

      connection =
        Integrations.create_github_connection!(pat,
          tenant: workspace.id,
          actor: owner
        )

      assert_raise Ash.Error.Forbidden, fn ->
        Integrations.delete_github_connection!(connection, actor: member)
      end
    end
  end

  describe "multitenancy" do
    test "connections are isolated between workspaces" do
      owner1 = generate(user())
      owner2 = generate(user())
      workspace1 = generate(workspace([], actor: owner1))
      workspace2 = generate(workspace([], actor: owner2))

      pat1 = "ghp_workspace1_token_#{System.unique_integer([:positive])}"
      pat2 = "ghp_workspace2_token_#{System.unique_integer([:positive])}"

      conn1 =
        Integrations.create_github_connection!(pat1,
          tenant: workspace1.id,
          actor: owner1
        )

      conn2 =
        Integrations.create_github_connection!(pat2,
          tenant: workspace2.id,
          actor: owner2
        )

      result1 =
        Integrations.get_workspace_github_connection!(workspace1.id,
          tenant: workspace1.id,
          actor: owner1
        )

      result2 =
        Integrations.get_workspace_github_connection!(workspace2.id,
          tenant: workspace2.id,
          actor: owner2
        )

      assert result1.id == conn1.id
      assert result2.id == conn2.id
      assert result1.pat_encrypted == pat1
      assert result2.pat_encrypted == pat2
    end
  end

  describe "direct Ash operations" do
    test "can read all connections for a workspace without authorization" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"

      Integrations.create_github_connection!(pat,
        tenant: workspace.id,
        actor: owner
      )

      {:ok, connections} =
        GitHubConnection
        |> Ash.Query.filter(workspace_id == ^workspace.id)
        |> Ash.read(authorize?: false, tenant: workspace.id)

      assert length(connections) == 1
      assert hd(connections).pat_encrypted == pat
    end
  end
end
