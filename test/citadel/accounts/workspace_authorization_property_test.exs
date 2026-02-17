defmodule Citadel.Accounts.WorkspaceAuthorizationPropertyTest do
  @moduledoc """
  Property-based tests for workspace authorization policies.

  These tests verify that authorization rules are consistent across
  all possible inputs and scenarios, testing thousands of random cases
  to ensure security boundaries hold universally.
  """
  use Citadel.DataCase, async: false

  alias Citadel.Accounts

  describe "workspace owner authorization properties" do
    property "workspace owners always have read access to their workspace" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Owner should always be able to read their workspace
        assert {:ok, found_workspace} =
                 Accounts.get_workspace_by_id(workspace.id, actor: owner)

        assert found_workspace.id == workspace.id
      end
    end

    property "workspace owners always have update access to their workspace" do
      check all(new_name_suffix <- integer(1..1000)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        new_name = "Updated Workspace #{new_name_suffix}"

        # Owner should always be able to update their workspace
        assert {:ok, updated_workspace} =
                 Accounts.update_workspace(workspace, %{name: new_name}, actor: owner)

        assert updated_workspace.name == new_name
      end
    end

    property "workspace owners always have destroy access to their workspace" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Owner should always be able to destroy their workspace
        assert :ok = Accounts.destroy_workspace(workspace, actor: owner)

        # Verify workspace is actually deleted (returns NotFound/Invalid)
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.get_workspace_by_id(workspace.id, actor: owner)
      end
    end

    property "workspace owners can always invite members to their workspace" do
      check all(email_suffix <- integer(1..1000)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        email = "invitee#{email_suffix}@example.com"

        # Owner should always be able to create invitations
        assert {:ok, invitation} =
                 Accounts.create_invitation(email, workspace.id, actor: owner)

        assert invitation.workspace_id == workspace.id
        assert String.downcase(to_string(invitation.email)) == String.downcase(email)
      end
    end

    property "workspace owners can always remove non-owner members" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))
        member = generate(user())

        # Add member using helper that handles org membership
        membership = add_user_to_workspace(member.id, workspace.id, actor: owner)

        # Owner should always be able to remove non-owner members
        assert :ok = Accounts.remove_workspace_member(membership, actor: owner)

        # Verify member is removed
        memberships =
          Accounts.list_workspace_members!(
            actor: owner,
            query: [filter: [user_id: member.id, workspace_id: workspace.id]]
          )

        assert memberships == []
      end
    end
  end

  describe "non-member authorization properties" do
    property "non-members are always forbidden from reading workspace" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        non_member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Non-member should not be able to see the workspace (NotFound)
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.get_workspace_by_id(workspace.id, actor: non_member)
      end
    end

    property "non-members are always forbidden from updating workspace" do
      check all(new_name_suffix <- integer(1..1000)) do
        owner = generate(user())
        non_member = generate(user())
        workspace = generate(workspace([], actor: owner))

        new_name = "Hacked Name #{new_name_suffix}"

        # Non-member should always be forbidden
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.update_workspace(
                   workspace,
                   %{name: new_name},
                   actor: non_member
                 )
      end
    end

    property "non-members are always forbidden from destroying workspace" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        non_member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Non-member should always be forbidden
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.destroy_workspace(workspace, actor: non_member)

        # Verify workspace still exists
        assert {:ok, _} = Accounts.get_workspace_by_id(workspace.id, actor: owner)
      end
    end

    property "non-members are always forbidden from inviting to workspace" do
      check all(email_suffix <- integer(1..1000)) do
        owner = generate(user())
        non_member = generate(user())
        workspace = generate(workspace([], actor: owner))

        email = "invitee#{email_suffix}@example.com"

        # Non-member should always be forbidden
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.create_invitation(email, workspace.id, actor: non_member)
      end
    end
  end

  describe "workspace member authorization properties" do
    property "workspace members always have read access" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Add member using helper that handles org membership
        add_user_to_workspace(member.id, workspace.id, actor: owner)

        # Member should always be able to read workspace
        assert {:ok, found_workspace} =
                 Accounts.get_workspace_by_id(workspace.id, actor: member)

        assert found_workspace.id == workspace.id
      end
    end

    property "workspace members can invite other members" do
      check all(email_suffix <- integer(1..1000)) do
        owner = generate(user())
        member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Add member using helper that handles org membership
        add_user_to_workspace(member.id, workspace.id, actor: owner)

        email = "new_member#{email_suffix}@example.com"

        # Members can invite others (per current policy)
        assert {:ok, invitation} =
                 Accounts.create_invitation(email, workspace.id, actor: member)

        assert invitation.workspace_id == workspace.id
      end
    end

    property "workspace members (non-owners) cannot update workspace" do
      check all(new_name_suffix <- integer(1..1000)) do
        owner = generate(user())
        member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Add member using helper that handles org membership
        add_user_to_workspace(member.id, workspace.id, actor: owner)

        new_name = "Member Updated #{new_name_suffix}"

        # Member should be forbidden from updating
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.update_workspace(
                   workspace,
                   %{name: new_name},
                   actor: member
                 )
      end
    end

    property "workspace members (non-owners) cannot destroy workspace" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Add member using helper that handles org membership
        add_user_to_workspace(member.id, workspace.id, actor: owner)

        # Member should be forbidden from destroying
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.destroy_workspace(workspace, actor: member)

        # Verify workspace still exists
        assert {:ok, _} = Accounts.get_workspace_by_id(workspace.id, actor: owner)
      end
    end
  end

  describe "cross-workspace authorization properties" do
    property "users in workspace A cannot access resources in workspace B" do
      check all(_ <- integer(1..25)) do
        owner_a = generate(user())
        workspace_a = generate(workspace([], actor: owner_a))
        owner_b = generate(user())
        workspace_b = generate(workspace([], actor: owner_b))

        # Owner A should not access workspace B (NotFound)
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.get_workspace_by_id(workspace_b.id, actor: owner_a)

        # Owner B should not access workspace A (NotFound)
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.get_workspace_by_id(workspace_a.id, actor: owner_b)
      end
    end

    property "users can access all and only their own workspaces" do
      check all(workspace_count <- integer(1..5), max_runs: 25) do
        user = generate(user())

        # Create multiple workspaces for this user
        workspaces =
          Enum.map(1..workspace_count, fn _ ->
            generate(workspace([], actor: user))
          end)

        workspace_ids = Enum.map(workspaces, & &1.id) |> MapSet.new()

        # User should be able to read all their workspaces
        for workspace <- workspaces do
          assert {:ok, found} =
                   Accounts.get_workspace_by_id(workspace.id, actor: user)

          assert found.id == workspace.id
        end

        # List should return exactly these workspaces
        listed_workspaces = Accounts.list_workspaces!(actor: user)
        listed_ids = Enum.map(listed_workspaces, & &1.id) |> MapSet.new()

        assert MapSet.equal?(workspace_ids, listed_ids)
      end
    end
  end
end
