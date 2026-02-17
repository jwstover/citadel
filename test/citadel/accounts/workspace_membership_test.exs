defmodule Citadel.Accounts.WorkspaceMembershipTest do
  use Citadel.DataCase, async: false

  alias Citadel.Accounts

  describe "add_workspace_member/3" do
    test "creates a membership when workspace owner invites a user" do
      owner = generate(user())
      member = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Add member to the organization first (required)
      Accounts.add_organization_member(workspace.organization_id, member.id, :member,
        authorize?: false
      )

      assert membership =
               Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      assert membership.user_id == member.id
      assert membership.workspace_id == workspace.id
    end

    test "raises error when duplicate membership is created" do
      owner = generate(user())
      member = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Add member to the organization first
      Accounts.add_organization_member(workspace.organization_id, member.id, :member,
        authorize?: false
      )

      # Create first membership
      Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      # Try to create duplicate membership
      assert_raise Ash.Error.Invalid, fn ->
        Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)
      end
    end

    test "raises error when user is not an org member" do
      owner = generate(user())
      non_member = generate(user())

      workspace = generate(workspace([], actor: owner))

      # User who is not an org member should not be able to be added
      assert_raise Ash.Error.Invalid, fn ->
        Accounts.add_workspace_member!(non_member.id, workspace.id, actor: owner)
      end
    end

    test "workspace member can invite other users" do
      owner = generate(user())
      member = generate(user())
      new_member = generate(user())

      workspace = generate(workspace([], actor: owner))
      org = Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)

      # Upgrade to pro to allow multiple members
      upgrade_to_pro(org)

      # Add members to the organization first
      Accounts.add_organization_member(workspace.organization_id, member.id, :member,
        authorize?: false
      )

      Accounts.add_organization_member(workspace.organization_id, new_member.id, :member,
        authorize?: false
      )

      # Owner adds first member
      Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      # Member can add another member
      assert membership =
               Accounts.add_workspace_member!(new_member.id, workspace.id, actor: member)

      assert membership.user_id == new_member.id
      assert membership.workspace_id == workspace.id
    end

    test "raises error when actor is missing" do
      owner = generate(user())
      member = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Add member to the organization first
      Accounts.add_organization_member(workspace.organization_id, member.id, :member,
        authorize?: false
      )

      # Should raise error without actor
      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.add_workspace_member!(member.id, workspace.id)
      end
    end
  end

  describe "list_workspace_members/1" do
    test "user can list their own memberships" do
      owner = generate(user())
      member = generate(user())

      # Create workspaces in separate orgs for owner
      workspace1 = generate(workspace([], actor: owner))
      workspace2 = generate(workspace([], actor: owner))

      # Add member to both organizations
      Accounts.add_organization_member(workspace1.organization_id, member.id, :member,
        authorize?: false
      )

      Accounts.add_organization_member(workspace2.organization_id, member.id, :member,
        authorize?: false
      )

      membership1 = Accounts.add_workspace_member!(member.id, workspace1.id, actor: owner)
      membership2 = Accounts.add_workspace_member!(member.id, workspace2.id, actor: owner)

      memberships = Accounts.list_workspace_members!(actor: member)
      membership_ids = Enum.map(memberships, & &1.id)

      assert membership1.id in membership_ids
      assert membership2.id in membership_ids
    end

    test "workspace members can see all memberships in their workspace" do
      owner = generate(user())
      member1 = generate(user())
      member2 = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Upgrade to pro to allow multiple members
      org = Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)
      upgrade_to_pro(org)

      # Add members to the organization first
      Accounts.add_organization_member(workspace.organization_id, member1.id, :member,
        authorize?: false
      )

      Accounts.add_organization_member(workspace.organization_id, member2.id, :member,
        authorize?: false
      )

      membership1 = Accounts.add_workspace_member!(member1.id, workspace.id, actor: owner)
      membership2 = Accounts.add_workspace_member!(member2.id, workspace.id, actor: owner)

      memberships = Accounts.list_workspace_members!(actor: member1)
      membership_ids = Enum.map(memberships, & &1.id)

      # Member1 can see all memberships in the workspace they belong to (including owner)
      assert membership1.id in membership_ids
      assert membership2.id in membership_ids
      assert length(memberships) == 3
    end

    test "returns empty list when user has no memberships" do
      user = generate(user())

      memberships = Accounts.list_workspace_members!(actor: user)
      assert memberships == []
    end

    test "can load workspace and user relationships" do
      owner = generate(user())
      member = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Add member to the organization first
      Accounts.add_organization_member(workspace.organization_id, member.id, :member,
        authorize?: false
      )

      _membership = Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      memberships =
        Accounts.list_workspace_members!(actor: member, load: [:workspace, :user])

      # Should see 2 memberships (owner + member)
      assert length(memberships) == 2

      # Find the member's membership
      loaded_membership = Enum.find(memberships, &(&1.user.id == member.id))
      assert loaded_membership.workspace.id == workspace.id
      assert loaded_membership.user.id == member.id
    end
  end

  describe "remove_workspace_member/2" do
    test "workspace owner can remove a member" do
      owner = generate(user())
      member = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Add member to the organization first
      Accounts.add_organization_member(workspace.organization_id, member.id, :member,
        authorize?: false
      )

      membership = Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      assert :ok = Accounts.remove_workspace_member!(membership, actor: owner)

      # Verify membership is gone
      memberships =
        Accounts.list_workspace_members!(actor: member, query: [filter: [id: membership.id]])

      assert memberships == []
    end

    test "raises error when non-owner tries to remove a member" do
      owner = generate(user())
      member1 = generate(user())
      member2 = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Upgrade to pro to allow multiple members
      org = Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)
      upgrade_to_pro(org)

      # Add members to the organization first
      Accounts.add_organization_member(workspace.organization_id, member1.id, :member,
        authorize?: false
      )

      Accounts.add_organization_member(workspace.organization_id, member2.id, :member,
        authorize?: false
      )

      membership1 = Accounts.add_workspace_member!(member1.id, workspace.id, actor: owner)
      _membership2 = Accounts.add_workspace_member!(member2.id, workspace.id, actor: owner)

      # Member should not be able to remove another member
      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.remove_workspace_member!(membership1, actor: member2)
      end
    end

    test "member can leave workspace by removing their own membership" do
      owner = generate(user())
      member = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Add member to the organization first
      Accounts.add_organization_member(workspace.organization_id, member.id, :member,
        authorize?: false
      )

      membership = Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      # Member leaving should succeed (owner can still remove)
      assert :ok = Accounts.remove_workspace_member!(membership, actor: owner)

      # Verify membership is gone
      memberships = Accounts.list_workspace_members!(actor: member)
      assert memberships == []
    end

    test "raises error when workspace owner tries to leave their own workspace" do
      owner = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Get the owner's automatically created membership
      [owner_membership] =
        Accounts.list_workspace_members!(
          actor: owner,
          query: [filter: [user_id: owner.id, workspace_id: workspace.id]]
        )

      # Owner should not be able to remove their own membership
      assert_raise Ash.Error.Invalid, fn ->
        Accounts.remove_workspace_member!(owner_membership, actor: owner)
      end
    end
  end

  describe "workspace relationships" do
    test "can load memberships from workspace" do
      owner = generate(user())
      member1 = generate(user())
      member2 = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Upgrade to pro to allow multiple members
      org = Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)
      upgrade_to_pro(org)

      # Add members to the organization first
      Accounts.add_organization_member(workspace.organization_id, member1.id, :member,
        authorize?: false
      )

      Accounts.add_organization_member(workspace.organization_id, member2.id, :member,
        authorize?: false
      )

      membership1 = Accounts.add_workspace_member!(member1.id, workspace.id, actor: owner)
      membership2 = Accounts.add_workspace_member!(member2.id, workspace.id, actor: owner)

      loaded_workspace =
        Accounts.get_workspace_by_id!(workspace.id, actor: owner, load: [:memberships])

      membership_ids = Enum.map(loaded_workspace.memberships, & &1.id)
      assert membership1.id in membership_ids
      assert membership2.id in membership_ids
    end

    test "can load members from workspace through many_to_many" do
      owner = generate(user())
      member1 = generate(user())
      member2 = generate(user())

      workspace = generate(workspace([], actor: owner))

      # Upgrade to pro to allow multiple members
      org = Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)
      upgrade_to_pro(org)

      # Add members to the organization first
      Accounts.add_organization_member(workspace.organization_id, member1.id, :member,
        authorize?: false
      )

      Accounts.add_organization_member(workspace.organization_id, member2.id, :member,
        authorize?: false
      )

      _membership1 = Accounts.add_workspace_member!(member1.id, workspace.id, actor: owner)
      _membership2 = Accounts.add_workspace_member!(member2.id, workspace.id, actor: owner)

      loaded_workspace =
        Accounts.get_workspace_by_id!(workspace.id, actor: owner, load: [:members])

      member_ids = Enum.map(loaded_workspace.members, & &1.id)
      assert member1.id in member_ids
      assert member2.id in member_ids
    end
  end
end
