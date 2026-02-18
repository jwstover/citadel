defmodule Citadel.Accounts.WorkspaceTest do
  use Citadel.DataCase, async: false

  alias Citadel.Accounts

  describe "create_workspace/2" do
    test "creates a workspace with valid attributes" do
      user = generate(user())

      workspace = generate(workspace([], actor: user))

      assert workspace.name != nil
      assert workspace.owner_id == user.id
    end

    test "creates a workspace with trimmed name" do
      user = generate(user())

      workspace = generate(workspace([name: "  Workspace with Spaces  "], actor: user))

      assert workspace.name == "Workspace with Spaces"
    end

    test "raises error when name is empty string" do
      user = generate(user())

      assert_raise Ash.Error.Invalid, fn ->
        generate(workspace([name: ""], actor: user))
      end
    end

    test "raises error when name exceeds maximum length" do
      user = generate(user())
      long_name = String.duplicate("a", 101)

      assert_raise Ash.Error.Invalid, fn ->
        generate(workspace([name: long_name], actor: user))
      end
    end

    test "raises error when actor is missing" do
      # The generator requires an actor, so we test the low-level action
      user = generate(user())
      org = generate(organization([], actor: user))

      assert_raise Ash.Error.Invalid, fn ->
        Citadel.Accounts.Workspace
        |> Ash.Changeset.for_create(:create, %{name: "Test", organization_id: org.id})
        |> Ash.create!()
      end
    end

    test "automatically sets owner to actor" do
      user = generate(user())

      workspace = generate(workspace([], actor: user))

      assert workspace.owner_id == user.id
    end
  end

  describe "list_workspaces/1" do
    test "returns workspaces where user is owner" do
      user = generate(user())

      workspace1 = generate(workspace([], actor: user))
      workspace2 = generate(workspace([], actor: user))

      workspaces = Accounts.list_workspaces!(actor: user)
      workspace_ids = Enum.map(workspaces, & &1.id)

      assert workspace1.id in workspace_ids
      assert workspace2.id in workspace_ids
    end

    test "does not return workspaces from other users" do
      user = generate(user())
      other_user = generate(user())

      other_workspace = generate(workspace([], actor: other_user))
      user_workspace = generate(workspace([], actor: user))

      workspaces = Accounts.list_workspaces!(actor: user)
      workspace_ids = Enum.map(workspaces, & &1.id)

      assert user_workspace.id in workspace_ids
      refute other_workspace.id in workspace_ids
    end

    test "returns empty list when user has no workspaces" do
      user = generate(user())

      workspaces = Accounts.list_workspaces!(actor: user)
      assert workspaces == []
    end

    test "can load owner relationship" do
      user = generate(user())

      _workspace = generate(workspace([], actor: user))

      workspaces = Accounts.list_workspaces!(actor: user, load: [:owner])

      assert length(workspaces) == 1
      loaded_workspace = hd(workspaces)
      assert loaded_workspace.owner.id == user.id
    end
  end

  describe "get_workspace_by_id/2" do
    test "gets a workspace by id when user is owner" do
      user = generate(user())

      workspace = generate(workspace([], actor: user))

      assert fetched = Accounts.get_workspace_by_id!(workspace.id, actor: user)
      assert fetched.id == workspace.id
      assert fetched.name == workspace.name
    end

    test "raises error when workspace does not exist" do
      user = generate(user())
      fake_id = Ash.UUID.generate()

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.get_workspace_by_id!(fake_id, actor: user)
      end
    end

    test "raises error when user is not a member" do
      owner = generate(user())
      other_user = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Other user should not be able to access the workspace
      assert_raise Ash.Error.Invalid, fn ->
        Accounts.get_workspace_by_id!(workspace.id, actor: other_user)
      end
    end
  end

  describe "update_workspace/3" do
    test "updates workspace name when user is owner" do
      user = generate(user())

      workspace = generate(workspace([], actor: user))

      updated = Accounts.update_workspace!(workspace, %{name: "New Name"}, actor: user)

      assert updated.id == workspace.id
      assert updated.name == "New Name"
    end

    test "raises error when non-owner tries to update" do
      owner = generate(user())
      other_user = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Other user should not be able to update
      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.update_workspace!(workspace, %{name: "Hacked Name"}, actor: other_user)
      end
    end

    test "raises error when updating with invalid name" do
      user = generate(user())

      workspace = generate(workspace([], actor: user))

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.update_workspace!(workspace, %{name: ""}, actor: user)
      end
    end
  end

  describe "destroy_workspace/2" do
    test "destroys workspace when user is owner" do
      user = generate(user())

      workspace = generate(workspace([], actor: user))

      assert :ok = Accounts.destroy_workspace!(workspace, actor: user)

      # Verify it's gone
      workspaces =
        Accounts.list_workspaces!(actor: user, query: [filter: [id: workspace.id]])

      assert workspaces == []
    end

    test "raises error when non-owner tries to destroy" do
      owner = generate(user())
      other_user = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Other user should not be able to destroy
      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.destroy_workspace!(workspace, actor: other_user)
      end
    end
  end

  describe "task_prefix" do
    test "workspace is assigned a task_prefix on creation" do
      user = generate(user())

      workspace = generate(workspace([name: "Test Workspace"], actor: user))

      assert workspace.task_prefix != nil
      assert is_binary(workspace.task_prefix)
    end

    test "task_prefix is 1-3 uppercase letters" do
      user = generate(user())

      workspace = generate(workspace([name: "Test Workspace"], actor: user))

      assert Regex.match?(~r/^[A-Z]{1,3}$/, workspace.task_prefix)
    end

    test "generates prefix from uppercase letters in name" do
      user = generate(user())

      # "My Project" has uppercase M and P
      workspace = generate(workspace([name: "My Project"], actor: user))
      assert workspace.task_prefix == "MP"

      # "Super Long Name" has uppercase S, L, N - takes all 3
      workspace2 = generate(workspace([name: "Super Long Name"], actor: user))
      assert workspace2.task_prefix == "SLN"
    end

    test "truncates prefix to 3 letters when more than 3 uppercase" do
      user = generate(user())

      # "ABCD Project" has 4 uppercase letters, should take first 3
      workspace = generate(workspace([name: "ABCD Project"], actor: user))
      assert workspace.task_prefix == "ABC"
    end

    @tag timeout: 60_000
    test "falls back to uppercasing first letters when no uppercase in name" do
      user = generate(user())

      # "acme corp" has no uppercase, takes first 3 letters uppercased
      workspace = generate(workspace([name: "acme corp"], actor: user))
      assert workspace.task_prefix == "ACM"
    end

    test "falls back to WS for empty or non-letter names" do
      user = generate(user())

      # Name with only numbers/special chars should fallback to WS
      workspace = generate(workspace([name: "123"], actor: user))
      assert workspace.task_prefix == "WS"
    end

    test "task_prefix is not changed on workspace update" do
      user = generate(user())

      workspace = generate(workspace([name: "Original Name"], actor: user))
      original_prefix = workspace.task_prefix

      updated = Accounts.update_workspace!(workspace, %{name: "New Name"}, actor: user)

      assert updated.task_prefix == original_prefix
    end
  end

  describe "current_workspace/1" do
    test "returns workspace matching the tenant" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      result = Accounts.current_workspace!(actor: user, tenant: workspace.id)

      assert result.id == workspace.id
    end

    test "returns full workspace record" do
      user = generate(user())
      workspace = generate(workspace([name: "Test Workspace"], actor: user))

      result = Accounts.current_workspace!(actor: user, tenant: workspace.id)

      assert result.id == workspace.id
      assert result.name == "Test Workspace"
      assert result.owner_id == user.id
      assert result.task_prefix != nil
    end

    test "raises error when tenant is not set" do
      user = generate(user())
      _workspace = generate(workspace([], actor: user))

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.current_workspace!(actor: user)
      end
    end

    test "raises error when tenant does not match any workspace" do
      user = generate(user())
      _workspace = generate(workspace([], actor: user))
      fake_id = Ash.UUID.generate()

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.current_workspace!(actor: user, tenant: fake_id)
      end
    end

    test "raises error when user is not a member of the workspace" do
      owner = generate(user())
      other_user = generate(user())
      workspace = generate(workspace([], actor: owner))

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.current_workspace!(actor: other_user, tenant: workspace.id)
      end
    end
  end
end
