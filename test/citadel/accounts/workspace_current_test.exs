defmodule Citadel.Accounts.WorkspaceCurrentTest do
  @moduledoc """
  Tests for the `:current` action on Workspace resource, specifically verifying
  that it correctly returns the workspace ID based on the tenant (from API key).

  These tests complement the basic tests in `workspace_test.exs` by focusing on
  the multi-workspace scenario where a user belongs to multiple workspaces and
  uses API keys scoped to different workspaces.
  """
  use Citadel.DataCase, async: true

  alias Citadel.Accounts
  alias Citadel.Accounts.ApiKey

  describe "current_workspace/1 with multiple workspaces" do
    test "returns correct workspace when user has multiple workspaces" do
      user = generate(user())

      workspace1 = generate(workspace([name: "Workspace One"], actor: user))
      workspace2 = generate(workspace([name: "Workspace Two"], actor: user))

      result1 = Accounts.current_workspace!(actor: user, tenant: workspace1.id)
      assert result1.id == workspace1.id

      result2 = Accounts.current_workspace!(actor: user, tenant: workspace2.id)
      assert result2.id == workspace2.id
    end

    test "returns correct workspace based on tenant regardless of creation order" do
      user = generate(user())

      first_workspace = generate(workspace([name: "First Created"], actor: user))
      second_workspace = generate(workspace([name: "Second Created"], actor: user))

      result_second = Accounts.current_workspace!(actor: user, tenant: second_workspace.id)
      assert result_second.id == second_workspace.id

      result_first = Accounts.current_workspace!(actor: user, tenant: first_workspace.id)
      assert result_first.id == first_workspace.id
    end

    test "user with membership in another user's workspace can access it via tenant" do
      owner = generate(user())
      member = generate(user())

      workspace = generate(workspace([name: "Shared Workspace"], actor: owner))

      generate(
        workspace_membership(
          [user_id: member.id, workspace_id: workspace.id],
          actor: owner
        )
      )

      result = Accounts.current_workspace!(actor: member, tenant: workspace.id)
      assert result.id == workspace.id
    end
  end

  describe "current_workspace/1 with API key authentication context" do
    test "workspace_id from API key determines correct tenant" do
      user = generate(user())

      workspace1 = generate(workspace([name: "API Workspace 1"], actor: user))
      workspace2 = generate(workspace([name: "API Workspace 2"], actor: user))

      expires_at = DateTime.add(DateTime.utc_now(), 30, :day)

      {:ok, api_key1} = create_api_key(user, workspace1, "Key for WS1", expires_at)
      {:ok, api_key2} = create_api_key(user, workspace2, "Key for WS2", expires_at)

      assert api_key1.workspace_id == workspace1.id
      assert api_key2.workspace_id == workspace2.id

      result1 = Accounts.current_workspace!(actor: user, tenant: api_key1.workspace_id)
      assert result1.id == workspace1.id

      result2 = Accounts.current_workspace!(actor: user, tenant: api_key2.workspace_id)
      assert result2.id == workspace2.id
    end

    test "API key workspace_id correctly scopes to specific workspace" do
      user = generate(user())

      owned_workspace = generate(workspace([name: "Owned"], actor: user))

      other_owner = generate(user())
      shared_workspace = generate(workspace([name: "Shared"], actor: other_owner))

      generate(
        workspace_membership(
          [user_id: user.id, workspace_id: shared_workspace.id],
          actor: other_owner
        )
      )

      expires_at = DateTime.add(DateTime.utc_now(), 30, :day)

      {:ok, owned_key} = create_api_key(user, owned_workspace, "Owned Key", expires_at)
      {:ok, shared_key} = create_api_key(user, shared_workspace, "Shared Key", expires_at)

      owned_result = Accounts.current_workspace!(actor: user, tenant: owned_key.workspace_id)
      assert owned_result.id == owned_workspace.id

      shared_result = Accounts.current_workspace!(actor: user, tenant: shared_key.workspace_id)
      assert shared_result.id == shared_workspace.id
    end

    test "different users with API keys to same workspace get same workspace_id" do
      owner = generate(user())
      member = generate(user())

      workspace = generate(workspace([name: "Team Workspace"], actor: owner))

      generate(
        workspace_membership(
          [user_id: member.id, workspace_id: workspace.id],
          actor: owner
        )
      )

      expires_at = DateTime.add(DateTime.utc_now(), 30, :day)

      {:ok, owner_key} = create_api_key(owner, workspace, "Owner Key", expires_at)
      {:ok, member_key} = create_api_key(member, workspace, "Member Key", expires_at)

      assert owner_key.workspace_id == member_key.workspace_id
      assert owner_key.workspace_id == workspace.id

      owner_result = Accounts.current_workspace!(actor: owner, tenant: owner_key.workspace_id)
      member_result = Accounts.current_workspace!(actor: member, tenant: member_key.workspace_id)

      assert owner_result.id == member_result.id
      assert owner_result.id == workspace.id
    end
  end

  describe "current_workspace/1 authorization" do
    test "user cannot access workspace they are not a member of via tenant" do
      owner = generate(user())
      non_member = generate(user())

      workspace = generate(workspace([name: "Private Workspace"], actor: owner))

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.current_workspace!(actor: non_member, tenant: workspace.id)
      end
    end

    test "user loses access after being removed from workspace" do
      owner = generate(user())
      member = generate(user())

      workspace = generate(workspace([name: "Temporary Access"], actor: owner))

      membership =
        generate(
          workspace_membership(
            [user_id: member.id, workspace_id: workspace.id],
            actor: owner
          )
        )

      result = Accounts.current_workspace!(actor: member, tenant: workspace.id)
      assert result.id == workspace.id

      Accounts.remove_workspace_member!(membership, actor: owner)

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.current_workspace!(actor: member, tenant: workspace.id)
      end
    end
  end

  defp create_api_key(user, workspace, name, expires_at) do
    ApiKey
    |> Ash.Changeset.for_create(:create, %{
      name: name,
      user_id: user.id,
      workspace_id: workspace.id,
      expires_at: expires_at
    })
    |> Ash.create(authorize?: false)
  end
end
