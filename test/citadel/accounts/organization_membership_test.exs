defmodule Citadel.Accounts.OrganizationMembershipTest do
  use Citadel.DataCase, async: true

  alias Citadel.Accounts

  describe "add_organization_member/4" do
    test "owner can add a member to their organization" do
      owner = create_user()
      new_member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      assert membership =
               Accounts.add_organization_member!(
                 organization.id,
                 new_member.id,
                 :member,
                 actor: owner
               )

      assert membership.user_id == new_member.id
      assert membership.organization_id == organization.id
      assert membership.role == :member
    end

    test "admin can add a member to the organization" do
      owner = create_user()
      admin = create_user()
      new_member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, admin.id, :admin, actor: owner)

      assert membership =
               Accounts.add_organization_member!(
                 organization.id,
                 new_member.id,
                 :member,
                 actor: admin
               )

      assert membership.role == :member
    end

    test "regular member cannot add other members" do
      owner = create_user()
      member = create_user()
      new_member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.add_organization_member!(
          organization.id,
          new_member.id,
          :member,
          actor: member
        )
      end
    end

    test "raises error when duplicate membership is created" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.add_organization_member!(organization.id, member.id, :admin, actor: owner)
      end
    end

    test "non-member cannot add members to organization" do
      owner = create_user()
      non_member = create_user()
      new_member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.add_organization_member!(
          organization.id,
          new_member.id,
          :member,
          actor: non_member
        )
      end
    end

    test "can add member with different roles" do
      owner = create_user()
      admin_user = create_user()
      member_user = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      admin_membership =
        Accounts.add_organization_member!(organization.id, admin_user.id, :admin, actor: owner)

      member_membership =
        Accounts.add_organization_member!(organization.id, member_user.id, :member, actor: owner)

      assert admin_membership.role == :admin
      assert member_membership.role == :member
    end
  end

  describe "list_organization_members/1" do
    test "member can list memberships in their organization" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      memberships =
        Accounts.list_organization_members!(
          actor: member,
          query: [filter: [organization_id: organization.id]]
        )

      assert length(memberships) == 2
      user_ids = Enum.map(memberships, & &1.user_id)
      assert owner.id in user_ids
      assert member.id in user_ids
    end

    test "user can see their own memberships across organizations" do
      owner = create_user()
      member = create_user()

      org1 = Accounts.create_organization!("Org 1", actor: owner)
      org2 = Accounts.create_organization!("Org 2", actor: owner)
      upgrade_to_pro(org1)
      upgrade_to_pro(org2)

      membership1 =
        Accounts.add_organization_member!(org1.id, member.id, :member, actor: owner)

      membership2 =
        Accounts.add_organization_member!(org2.id, member.id, :admin, actor: owner)

      memberships =
        Accounts.list_organization_members!(
          actor: member,
          query: [filter: [user_id: member.id]]
        )

      membership_ids = Enum.map(memberships, & &1.id)
      assert membership1.id in membership_ids
      assert membership2.id in membership_ids
    end

    test "can load user and organization relationships" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      _membership =
        Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      memberships =
        Accounts.list_organization_members!(
          actor: member,
          load: [:user, :organization],
          query: [filter: [user_id: member.id]]
        )

      [loaded_membership] = memberships
      assert loaded_membership.user.id == member.id
      assert loaded_membership.organization.id == organization.id
    end
  end

  describe "update_organization_member_role/2" do
    test "owner can update member role" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      membership =
        Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      assert membership.role == :member

      updated =
        Accounts.update_organization_member_role!(membership, %{role: :admin}, actor: owner)

      assert updated.role == :admin
    end

    test "admin can update member role" do
      owner = create_user()
      admin = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, admin.id, :admin, actor: owner)

      membership =
        Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      updated =
        Accounts.update_organization_member_role!(membership, %{role: :admin}, actor: admin)

      assert updated.role == :admin
    end

    test "regular member cannot update roles" do
      owner = create_user()
      member1 = create_user()
      member2 = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member1.id, :member, actor: owner)

      membership2 =
        Accounts.add_organization_member!(organization.id, member2.id, :member, actor: owner)

      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.update_organization_member_role!(membership2, %{role: :admin}, actor: member1)
      end
    end
  end

  describe "remove_organization_member/2" do
    test "owner can remove a member" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      membership =
        Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      assert :ok = Accounts.remove_organization_member!(membership, actor: owner)

      memberships =
        Accounts.list_organization_members!(
          actor: owner,
          query: [filter: [organization_id: organization.id]]
        )

      user_ids = Enum.map(memberships, & &1.user_id)
      refute member.id in user_ids
    end

    test "member can leave organization (remove their own membership)" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      membership =
        Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      assert :ok = Accounts.remove_organization_member!(membership, actor: member)
    end

    test "owner cannot leave their own organization" do
      owner = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)

      [owner_membership] =
        Accounts.list_organization_members!(
          actor: owner,
          query: [filter: [organization_id: organization.id, user_id: owner.id]]
        )

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.remove_organization_member!(owner_membership, actor: owner)
      end
    end

    test "non-owner/non-self cannot remove members" do
      owner = create_user()
      member1 = create_user()
      member2 = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member1.id, :member, actor: owner)

      membership2 =
        Accounts.add_organization_member!(organization.id, member2.id, :member, actor: owner)

      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.remove_organization_member!(membership2, actor: member1)
      end
    end
  end

  describe "workspace membership requires organization membership" do
    test "org member can be added to workspace" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      workspace =
        Accounts.Workspace
        |> Ash.Changeset.for_create(
          :create,
          %{name: "Test Workspace", organization_id: organization.id},
          actor: owner
        )
        |> Ash.create!()

      assert membership =
               Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      assert membership.user_id == member.id
    end

    test "non-org member cannot be added to workspace" do
      owner = create_user()
      non_member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)

      workspace =
        Accounts.Workspace
        |> Ash.Changeset.for_create(
          :create,
          %{name: "Test Workspace", organization_id: organization.id},
          actor: owner
        )
        |> Ash.create!()

      assert_raise Ash.Error.Invalid,
                   ~r/user must be a member of the workspace's organization/,
                   fn ->
                     Accounts.add_workspace_member!(non_member.id, workspace.id, actor: owner)
                   end
    end

    test "workspace without organization allows any user (backwards compatibility)" do
      owner = create_user()
      other_user = create_user()

      workspace = Accounts.create_workspace!("Test Workspace", actor: owner)

      assert membership =
               Accounts.add_workspace_member!(other_user.id, workspace.id, actor: owner)

      assert membership.user_id == other_user.id
    end
  end
end
