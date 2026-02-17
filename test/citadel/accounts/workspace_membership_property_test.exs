defmodule Citadel.Accounts.WorkspaceMembershipPropertyTest do
  @moduledoc """
  Property-based tests for workspace membership business rules and data integrity.

  These tests verify:
  - Owner cannot leave workspace (critical business rule)
  - Non-owners can always leave
  - Duplicate memberships are prevented
  - Membership identity constraints
  """
  use Citadel.DataCase, async: true

  alias Citadel.Accounts

  describe "owner leaving prevention properties" do
    property "workspace owner can never leave their own workspace" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Get owner's membership (automatically created when workspace is created)
        [owner_membership] =
          Accounts.list_workspace_members!(
            actor: owner,
            query: [filter: [user_id: owner.id, workspace_id: workspace.id]]
          )

        # Owner should NEVER be able to leave their workspace
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.remove_workspace_member(owner_membership, actor: owner)

        # Verify membership still exists
        memberships =
          Accounts.list_workspace_members!(
            actor: owner,
            query: [filter: [user_id: owner.id, workspace_id: workspace.id]]
          )

        assert length(memberships) == 1
      end
    end

    property "owner cannot be removed by anyone, including themselves" do
      check all(_ <- integer(1..50)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))
        other_user = generate(user())

        # Get owner's membership
        [owner_membership] =
          Accounts.list_workspace_members!(
            actor: owner,
            query: [filter: [user_id: owner.id, workspace_id: workspace.id]]
          )

        # Owner can't remove themselves
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.remove_workspace_member(owner_membership, actor: owner)

        # Other users also can't remove owner (validation catches it before authorization)
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.remove_workspace_member(owner_membership, actor: other_user)

        # Verify membership still exists
        memberships =
          Accounts.list_workspace_members!(
            actor: owner,
            query: [filter: [user_id: owner.id, workspace_id: workspace.id]]
          )

        assert length(memberships) == 1
      end
    end
  end

  describe "non-owner leaving properties" do
    property "non-owner members can always leave their memberships" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Add member using helper that handles org membership
        membership = add_user_to_workspace(member.id, workspace.id, actor: owner)

        # Member leaving should always succeed (by owner's action)
        assert :ok = Accounts.remove_workspace_member(membership, actor: owner)

        # Verify membership is gone
        memberships =
          Accounts.list_workspace_members!(
            actor: owner,
            query: [filter: [user_id: member.id, workspace_id: workspace.id]]
          )

        assert memberships == []
      end
    end

    property "multiple non-owner members can all leave" do
      check all(member_count <- integer(1..10), max_runs: 20) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Upgrade to pro tier to allow multiple members
        org = Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)
        upgrade_to_pro(org)

        # Add multiple members using helper that handles org membership
        members_and_memberships =
          for _ <- 1..member_count do
            member = generate(user())
            membership = add_user_to_workspace(member.id, workspace.id, actor: owner)
            {member, membership}
          end

        # Each member should be able to leave
        for {_member, membership} <- members_and_memberships do
          assert :ok = Accounts.remove_workspace_member(membership, actor: owner)
        end

        # Only owner should remain
        remaining_memberships =
          Accounts.list_workspace_members!(actor: owner)

        # Should only be owner's membership
        assert length(remaining_memberships) == 1
        assert hd(remaining_memberships).user_id == owner.id
      end
    end
  end

  describe "duplicate membership prevention properties" do
    property "duplicate workspace memberships always fail" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # First membership should succeed using helper
        membership = add_user_to_workspace(member.id, workspace.id, actor: owner)
        assert membership != nil

        # Second membership attempt should fail
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.add_workspace_member(member.id, workspace.id, actor: owner)

        # Verify only one membership exists
        memberships =
          Accounts.list_workspace_members!(
            actor: owner,
            query: [filter: [user_id: member.id, workspace_id: workspace.id]]
          )

        assert length(memberships) == 1
      end
    end

    property "multiple attempts to add same member always result in single membership" do
      check all(attempt_count <- integer(2..5)) do
        owner = generate(user())
        member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # First attempt using helper (succeeds)
        first_result = {:ok, add_user_to_workspace(member.id, workspace.id, actor: owner)}

        # Additional attempts directly (should all fail since user is already a member)
        additional_results =
          for _ <- 2..attempt_count do
            Accounts.add_workspace_member(member.id, workspace.id, actor: owner)
          end

        results = [first_result | additional_results]

        # First should succeed, rest should fail
        assert Enum.count(results, &match?({:ok, _}, &1)) == 1
        assert Enum.count(results, &match?({:error, _}, &1)) == attempt_count - 1

        # Verify only one membership exists
        memberships =
          Accounts.list_workspace_members!(
            actor: owner,
            query: [filter: [user_id: member.id, workspace_id: workspace.id]]
          )

        assert length(memberships) == 1
      end
    end
  end

  describe "membership identity constraint properties" do
    property "user can only have one membership per workspace" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Add member once using helper
        add_user_to_workspace(member.id, workspace.id, actor: owner)

        # Attempting to add again should fail due to identity constraint
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.add_workspace_member(member.id, workspace.id, actor: owner)
      end
    end

    property "user can be member of multiple different workspaces" do
      check all(workspace_count <- integer(2..5), max_runs: 25) do
        user = generate(user())

        # Create multiple workspaces and add user to all of them
        workspaces_and_memberships =
          for _ <- 1..workspace_count do
            owner = generate(user())
            workspace = generate(workspace([], actor: owner))

            # Use helper to add user to workspace (handles org membership)
            membership = add_user_to_workspace(user.id, workspace.id, actor: owner)

            {workspace, membership}
          end

        # User should have exactly workspace_count memberships
        all_memberships =
          Accounts.list_workspace_members!(
            actor: user,
            query: [filter: [user_id: user.id]]
          )

        assert length(all_memberships) >= workspace_count

        # Verify each workspace has the membership
        for {workspace, _membership} <- workspaces_and_memberships do
          memberships_in_workspace =
            Accounts.list_workspace_members!(
              actor: user,
              query: [filter: [user_id: user.id, workspace_id: workspace.id]]
            )

          assert length(memberships_in_workspace) == 1
        end
      end
    end
  end

  describe "membership add/remove cycle properties" do
    property "adding and removing member multiple times works correctly" do
      check all(cycle_count <- integer(1..5)) do
        owner = generate(user())
        member = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Perform multiple add/remove cycles
        for i <- 1..cycle_count do
          # Add member - first time use helper, subsequent times org membership already exists
          membership =
            if i == 1 do
              add_user_to_workspace(member.id, workspace.id, actor: owner)
            else
              Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)
            end

          # Verify member is added
          memberships =
            Accounts.list_workspace_members!(
              actor: owner,
              query: [filter: [user_id: member.id, workspace_id: workspace.id]]
            )

          assert length(memberships) == 1

          # Remove member
          Accounts.remove_workspace_member!(membership, actor: owner)

          # Verify member is removed
          memberships_after =
            Accounts.list_workspace_members!(
              actor: owner,
              query: [filter: [user_id: member.id, workspace_id: workspace.id]]
            )

          assert memberships_after == []
        end
      end
    end
  end
end
