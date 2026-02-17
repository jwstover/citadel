defmodule Citadel.Accounts.OrganizationTest do
  use Citadel.DataCase, async: true

  alias Citadel.Accounts

  describe "create_organization/2" do
    test "creates an organization with valid name" do
      owner = create_user()
      name = "Test Org #{System.unique_integer([:positive])}"

      assert organization = Accounts.create_organization!(name, actor: owner)
      assert organization.name == name
      assert organization.owner_id == owner.id
      assert organization.slug != nil
    end

    test "auto-generates a unique slug from the name" do
      owner = create_user()

      org1 = Accounts.create_organization!("My Organization", actor: owner)
      org2 = Accounts.create_organization!("My Organization", actor: owner)

      assert org1.slug != org2.slug
      assert String.starts_with?(org1.slug, "my-organization")
      assert String.starts_with?(org2.slug, "my-organization")
    end

    test "automatically creates organization membership for owner" do
      owner = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)

      memberships =
        Accounts.list_organization_members!(
          actor: owner,
          query: [filter: [organization_id: organization.id]]
        )

      assert length(memberships) == 1
      [membership] = memberships
      assert membership.user_id == owner.id
      assert membership.organization_id == organization.id
      assert membership.role == :owner
    end

    test "raises error when name is too short" do
      owner = create_user()

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.create_organization!("", actor: owner)
      end
    end

    test "raises error when name is too long" do
      owner = create_user()
      long_name = String.duplicate("a", 101)

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.create_organization!(long_name, actor: owner)
      end
    end

    test "raises error when actor is missing" do
      assert_raise Ash.Error.Invalid, fn ->
        Accounts.create_organization!("Test Org")
      end
    end
  end

  describe "get_organization_by_id/2" do
    test "owner can read their organization" do
      owner = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)

      assert fetched = Accounts.get_organization_by_id!(organization.id, actor: owner)
      assert fetched.id == organization.id
    end

    test "organization member can read the organization" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      assert fetched = Accounts.get_organization_by_id!(organization.id, actor: member)
      assert fetched.id == organization.id
    end

    test "non-member cannot read the organization" do
      owner = create_user()
      non_member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.get_organization_by_id!(organization.id, actor: non_member)
      end
    end
  end

  describe "get_organization_by_slug/2" do
    test "can fetch organization by slug" do
      owner = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)

      assert fetched = Accounts.get_organization_by_slug!(organization.slug, actor: owner)
      assert fetched.id == organization.id
    end
  end

  describe "update_organization/2" do
    test "owner can update organization name" do
      owner = create_user()
      organization = Accounts.create_organization!("Original Name", actor: owner)

      assert updated =
               Accounts.update_organization!(organization, %{name: "Updated Name"}, actor: owner)

      assert updated.name == "Updated Name"
    end

    test "admin member can update organization" do
      owner = create_user()
      admin = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, admin.id, :admin, actor: owner)

      assert updated =
               Accounts.update_organization!(organization, %{name: "Admin Updated"}, actor: admin)

      assert updated.name == "Admin Updated"
    end

    test "regular member cannot update organization" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.update_organization!(organization, %{name: "Member Updated"}, actor: member)
      end
    end

    test "non-member cannot update organization" do
      owner = create_user()
      non_member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)

      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.update_organization!(organization, %{name: "Hacked"}, actor: non_member)
      end
    end
  end

  describe "destroy_organization/2" do
    test "owner can destroy organization" do
      owner = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)

      assert :ok = Accounts.destroy_organization!(organization, actor: owner)

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.get_organization_by_id!(organization.id, actor: owner)
      end
    end

    test "admin cannot destroy organization" do
      owner = create_user()
      admin = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, admin.id, :admin, actor: owner)

      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.destroy_organization!(organization, actor: admin)
      end
    end

    test "regular member cannot destroy organization" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.destroy_organization!(organization, actor: member)
      end
    end
  end

  describe "list_organizations/1" do
    test "user can list organizations they are a member of" do
      owner = create_user()
      member = create_user()

      org1 = Accounts.create_organization!("Org 1", actor: owner)
      org2 = Accounts.create_organization!("Org 2", actor: owner)
      _org3 = Accounts.create_organization!("Org 3 (not member)", actor: owner)
      upgrade_to_pro(org1)
      upgrade_to_pro(org2)

      Accounts.add_organization_member!(org1.id, member.id, :member, actor: owner)
      Accounts.add_organization_member!(org2.id, member.id, :member, actor: owner)

      organizations = Accounts.list_organizations!(actor: member)
      org_ids = Enum.map(organizations, & &1.id)

      assert org1.id in org_ids
      assert org2.id in org_ids
      assert length(organizations) == 2
    end
  end

  describe "organization relationships" do
    @tag timeout: 120_000
    test "can load memberships from organization" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      loaded_org =
        Accounts.get_organization_by_id!(organization.id, actor: owner, load: [:memberships])

      assert length(loaded_org.memberships) == 2

      user_ids = Enum.map(loaded_org.memberships, & &1.user_id)
      assert owner.id in user_ids
      assert member.id in user_ids
    end

    @tag timeout: 120_000
    test "can load members through many_to_many" do
      owner = create_user()
      member = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      Accounts.add_organization_member!(organization.id, member.id, :member, actor: owner)

      loaded_org =
        Accounts.get_organization_by_id!(organization.id, actor: owner, load: [:members])

      member_ids = Enum.map(loaded_org.members, & &1.id)
      assert owner.id in member_ids
      assert member.id in member_ids
    end

    @tag timeout: 120_000
    test "can load workspaces from organization" do
      owner = create_user()
      organization = Accounts.create_organization!("Test Org", actor: owner)
      upgrade_to_pro(organization)

      workspace1 =
        Accounts.Workspace
        |> Ash.Changeset.for_create(
          :create,
          %{name: "Workspace 1", organization_id: organization.id},
          actor: owner
        )
        |> Ash.create!()

      workspace2 =
        Accounts.Workspace
        |> Ash.Changeset.for_create(
          :create,
          %{name: "Workspace 2", organization_id: organization.id},
          actor: owner
        )
        |> Ash.create!()

      loaded_org =
        Accounts.get_organization_by_id!(organization.id, actor: owner, load: [:workspaces])

      workspace_ids = Enum.map(loaded_org.workspaces, & &1.id)
      assert workspace1.id in workspace_ids
      assert workspace2.id in workspace_ids
    end
  end
end
