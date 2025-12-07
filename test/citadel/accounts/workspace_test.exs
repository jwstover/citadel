defmodule Citadel.Accounts.WorkspaceTest do
  use Citadel.DataCase, async: true

  alias Citadel.Accounts

  describe "create_workspace/2" do
    test "creates a workspace with valid attributes" do
      user = create_user()

      name = "Test Workspace #{System.unique_integer([:positive])}"

      assert workspace = Accounts.create_workspace!(name, actor: user)
      assert workspace.name == name
      assert workspace.owner_id == user.id
    end

    test "creates a workspace with trimmed name" do
      user = create_user()

      name = "  Workspace with Spaces  "

      assert workspace = Accounts.create_workspace!(name, actor: user)
      assert workspace.name == "Workspace with Spaces"
    end

    test "raises error when name is empty string" do
      user = create_user()

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.create_workspace!("", actor: user)
      end
    end

    test "raises error when name exceeds maximum length" do
      user = create_user()

      long_name = String.duplicate("a", 101)

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.create_workspace!(long_name, actor: user)
      end
    end

    test "raises error when actor is missing" do
      name = "Workspace #{System.unique_integer([:positive])}"

      # Raises Invalid because relate_actor fails before authorization check
      assert_raise Ash.Error.Invalid, fn ->
        Accounts.create_workspace!(name)
      end
    end

    test "automatically sets owner to actor" do
      user = create_user()

      workspace = Accounts.create_workspace!("My Workspace", actor: user)

      assert workspace.owner_id == user.id
    end
  end

  describe "list_workspaces/1" do
    test "returns workspaces where user is owner" do
      user = create_user()

      workspace1 =
        Accounts.create_workspace!(
          "Workspace 1 #{System.unique_integer([:positive])}",
          actor: user
        )

      workspace2 =
        Accounts.create_workspace!(
          "Workspace 2 #{System.unique_integer([:positive])}",
          actor: user
        )

      workspaces = Accounts.list_workspaces!(actor: user)
      workspace_ids = Enum.map(workspaces, & &1.id)

      assert workspace1.id in workspace_ids
      assert workspace2.id in workspace_ids
    end

    test "does not return workspaces from other users" do
      user = create_user()
      other_user = create_user()

      other_workspace =
        Accounts.create_workspace!(
          "Other Workspace #{System.unique_integer([:positive])}",
          actor: other_user
        )

      user_workspace =
        Accounts.create_workspace!(
          "User Workspace #{System.unique_integer([:positive])}",
          actor: user
        )

      workspaces = Accounts.list_workspaces!(actor: user)
      workspace_ids = Enum.map(workspaces, & &1.id)

      assert user_workspace.id in workspace_ids
      refute other_workspace.id in workspace_ids
    end

    test "returns empty list when user has no workspaces" do
      user = create_user()

      workspaces = Accounts.list_workspaces!(actor: user)
      assert workspaces == []
    end

    test "can load owner relationship" do
      user = create_user()

      _workspace =
        Accounts.create_workspace!(
          "Workspace #{System.unique_integer([:positive])}",
          actor: user
        )

      workspaces = Accounts.list_workspaces!(actor: user, load: [:owner])

      assert length(workspaces) == 1
      loaded_workspace = hd(workspaces)
      assert loaded_workspace.owner.id == user.id
    end
  end

  describe "get_workspace_by_id/2" do
    test "gets a workspace by id when user is owner" do
      user = create_user()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: user
        )

      assert fetched = Accounts.get_workspace_by_id!(workspace.id, actor: user)
      assert fetched.id == workspace.id
      assert fetched.name == workspace.name
    end

    test "raises error when workspace does not exist" do
      user = create_user()
      fake_id = Ash.UUID.generate()

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.get_workspace_by_id!(fake_id, actor: user)
      end
    end

    test "raises error when user is not a member" do
      owner = create_user()
      other_user = create_user()

      workspace =
        Accounts.create_workspace!(
          "Private Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      # Other user should not be able to access the workspace
      assert_raise Ash.Error.Invalid, fn ->
        Accounts.get_workspace_by_id!(workspace.id, actor: other_user)
      end
    end
  end

  describe "update_workspace/3" do
    test "updates workspace name when user is owner" do
      user = create_user()

      workspace =
        Accounts.create_workspace!(
          "Original Name #{System.unique_integer([:positive])}",
          actor: user
        )

      updated = Accounts.update_workspace!(workspace, %{name: "New Name"}, actor: user)

      assert updated.id == workspace.id
      assert updated.name == "New Name"
    end

    test "raises error when non-owner tries to update" do
      owner = create_user()
      other_user = create_user()

      workspace =
        Accounts.create_workspace!(
          "Protected Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      # Other user should not be able to update
      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.update_workspace!(workspace, %{name: "Hacked Name"}, actor: other_user)
      end
    end

    test "raises error when updating with invalid name" do
      user = create_user()

      workspace =
        Accounts.create_workspace!(
          "Valid Name #{System.unique_integer([:positive])}",
          actor: user
        )

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.update_workspace!(workspace, %{name: ""}, actor: user)
      end
    end
  end

  describe "destroy_workspace/2" do
    test "destroys workspace when user is owner" do
      user = create_user()

      workspace =
        Accounts.create_workspace!(
          "To Delete #{System.unique_integer([:positive])}",
          actor: user
        )

      assert :ok = Accounts.destroy_workspace!(workspace, actor: user)

      # Verify it's gone
      workspaces =
        Accounts.list_workspaces!(actor: user, query: [filter: [id: workspace.id]])

      assert workspaces == []
    end

    test "raises error when non-owner tries to destroy" do
      owner = create_user()
      other_user = create_user()

      workspace =
        Accounts.create_workspace!(
          "Protected Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      # Other user should not be able to destroy
      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.destroy_workspace!(workspace, actor: other_user)
      end
    end
  end

  describe "task_prefix" do
    test "workspace is assigned a task_prefix on creation" do
      user = create_user()

      workspace = Accounts.create_workspace!("Test Workspace", actor: user)

      assert workspace.task_prefix != nil
      assert is_binary(workspace.task_prefix)
    end

    test "task_prefix is 1-3 uppercase letters" do
      user = create_user()

      workspace = Accounts.create_workspace!("Test Workspace", actor: user)

      assert Regex.match?(~r/^[A-Z]{1,3}$/, workspace.task_prefix)
    end

    test "generates prefix from uppercase letters in name" do
      user = create_user()

      # "My Project" has uppercase M and P
      workspace = Accounts.create_workspace!("My Project", actor: user)
      assert workspace.task_prefix == "MP"

      # "Super Long Name" has uppercase S, L, N - takes all 3
      workspace2 = Accounts.create_workspace!("Super Long Name", actor: user)
      assert workspace2.task_prefix == "SLN"
    end

    test "truncates prefix to 3 letters when more than 3 uppercase" do
      user = create_user()

      # "ABCD Project" has 4 uppercase letters, should take first 3
      workspace = Accounts.create_workspace!("ABCD Project", actor: user)
      assert workspace.task_prefix == "ABC"
    end

    test "falls back to uppercasing first letters when no uppercase in name" do
      user = create_user()

      # "acme corp" has no uppercase, takes first 3 letters uppercased
      workspace = Accounts.create_workspace!("acme corp", actor: user)
      assert workspace.task_prefix == "ACM"
    end

    test "falls back to WS for empty or non-letter names" do
      user = create_user()

      # Name with only numbers/special chars should fallback to WS
      workspace = Accounts.create_workspace!("123", actor: user)
      assert workspace.task_prefix == "WS"
    end

    test "task_prefix is not changed on workspace update" do
      user = create_user()

      workspace = Accounts.create_workspace!("Original Name", actor: user)
      original_prefix = workspace.task_prefix

      updated = Accounts.update_workspace!(workspace, %{name: "New Name"}, actor: user)

      assert updated.task_prefix == original_prefix
    end
  end
end
