defmodule Citadel.Accounts.WorkspaceInvitationTest do
  use Citadel.DataCase, async: false

  alias Citadel.Accounts

  describe "create_invitation/3" do
    test "creates an invitation with valid email and workspace" do
      owner = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      assert invitation =
               Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      assert to_string(invitation.email) == invitee_email
      assert invitation.workspace_id == workspace.id
      assert invitation.invited_by_id == owner.id
      assert not is_nil(invitation.token)
      assert not is_nil(invitation.expires_at)
      assert is_nil(invitation.accepted_at)
    end

    test "auto-generates a secure token" do
      owner = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      assert String.length(invitation.token) > 30
      assert invitation.token =~ ~r/^[A-Za-z0-9_-]+$/
    end

    test "tokens are unique across invitations" do
      owner = generate(user())
      email1 = unique_user_email()
      email2 = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      invitation1 = Accounts.create_invitation!(email1, workspace.id, actor: owner)
      invitation2 = Accounts.create_invitation!(email2, workspace.id, actor: owner)

      assert invitation1.token != invitation2.token
    end

    test "sets expires_at to 7 days from now" do
      owner = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      seven_days_from_now = DateTime.add(DateTime.utc_now(), 7, :day)
      diff = DateTime.diff(invitation.expires_at, seven_days_from_now, :second)

      assert abs(diff) < 5
    end

    test "workspace member can create invitation" do
      owner = generate(user())
      member = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      add_user_to_workspace(member.id, workspace.id, actor: owner)

      assert invitation =
               Accounts.create_invitation!(invitee_email, workspace.id, actor: member)

      assert invitation.invited_by_id == member.id
    end

    test "raises error when non-member tries to create invitation" do
      owner = generate(user())
      non_member = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.create_invitation!(invitee_email, workspace.id, actor: non_member)
      end
    end
  end

  describe "list_workspace_invitations/1" do
    test "workspace members can list invitations for their workspace" do
      owner = generate(user())
      email1 = unique_user_email()
      email2 = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      invitation1 = Accounts.create_invitation!(email1, workspace.id, actor: owner)
      invitation2 = Accounts.create_invitation!(email2, workspace.id, actor: owner)

      invitations =
        Accounts.list_workspace_invitations!(
          actor: owner,
          query: [filter: [workspace_id: workspace.id]]
        )

      invitation_ids = Enum.map(invitations, & &1.id)
      assert invitation1.id in invitation_ids
      assert invitation2.id in invitation_ids
    end

    test "non-members cannot list workspace invitations" do
      owner = generate(user())
      non_member = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      _invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      invitations =
        Accounts.list_workspace_invitations!(
          actor: non_member,
          query: [filter: [workspace_id: workspace.id]]
        )

      assert invitations == []
    end
  end

  describe "get_invitation_by_token/2" do
    test "anyone can get invitation by token" do
      owner = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      fetched = Accounts.get_invitation_by_token!(invitation.token)

      assert fetched.id == invitation.id
      assert to_string(fetched.email) == invitee_email
    end
  end

  describe "accept_invitation/2" do
    test "accepts invitation and creates workspace membership" do
      owner = generate(user())
      invitee = generate(user())
      workspace = generate(workspace([], actor: owner))

      Accounts.add_organization_member(
        workspace.organization_id,
        invitee.id,
        :member,
        authorize?: false
      )

      invitation = Accounts.create_invitation!(invitee.email, workspace.id, actor: owner)

      accepted = Accounts.accept_invitation!(invitation)

      assert not is_nil(accepted.accepted_at)

      memberships =
        Accounts.list_workspace_members!(actor: invitee, query: [filter: [user_id: invitee.id]])

      assert length(memberships) == 1
      membership = hd(memberships)
      assert membership.workspace_id == workspace.id
      assert membership.user_id == invitee.id
    end

    test "raises error when accepting expired invitation" do
      owner = generate(user())
      invitee = generate(user())
      workspace = generate(workspace([], actor: owner))

      Accounts.add_organization_member(
        workspace.organization_id,
        invitee.id,
        :member,
        authorize?: false
      )

      invitation =
        Accounts.create_invitation!(invitee.email, workspace.id, actor: owner)
        |> Ash.Changeset.for_update(:update, %{
          expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
        })
        |> Ash.update!(authorize?: false)

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.accept_invitation!(invitation)
      end
    end

    test "raises error when accepting already accepted invitation" do
      owner = generate(user())
      invitee = generate(user())
      workspace = generate(workspace([], actor: owner))

      Accounts.add_organization_member(
        workspace.organization_id,
        invitee.id,
        :member,
        authorize?: false
      )

      invitation = Accounts.create_invitation!(invitee.email, workspace.id, actor: owner)

      Accounts.accept_invitation!(invitation)

      invitation = Accounts.get_invitation_by_token!(invitation.token)

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.accept_invitation!(invitation)
      end
    end

    test "raises error when user email doesn't exist" do
      owner = generate(user())
      non_existent_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      invitation = Accounts.create_invitation!(non_existent_email, workspace.id, actor: owner)

      assert_raise Ash.Error.Unknown, fn ->
        Accounts.accept_invitation!(invitation)
      end
    end
  end

  describe "revoke_invitation/2" do
    test "workspace owner can revoke invitation" do
      owner = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      assert :ok = Accounts.revoke_invitation!(invitation, actor: owner)

      assert_raise Ash.Error.Invalid, fn ->
        Accounts.get_invitation_by_token!(invitation.token)
      end
    end

    test "raises error when non-owner tries to revoke invitation" do
      owner = generate(user())
      member = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      add_user_to_workspace(member.id, workspace.id, actor: owner)

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.revoke_invitation!(invitation, actor: member)
      end
    end
  end

  describe "calculations" do
    test "is_expired returns true for expired invitations" do
      owner = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      invitation =
        Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)
        |> Ash.Changeset.for_update(:update, %{
          expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
        })
        |> Ash.update!(authorize?: false)

      invitation = Accounts.get_invitation_by_token!(invitation.token, load: [:is_expired])

      assert invitation.is_expired == true
    end

    test "is_expired returns false for non-expired invitations" do
      owner = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      invitation = Accounts.get_invitation_by_token!(invitation.token, load: [:is_expired])

      assert invitation.is_expired == false
    end

    test "is_accepted returns true for accepted invitations" do
      owner = generate(user())
      invitee = generate(user())
      workspace = generate(workspace([], actor: owner))

      Accounts.add_organization_member(
        workspace.organization_id,
        invitee.id,
        :member,
        authorize?: false
      )

      invitation = Accounts.create_invitation!(invitee.email, workspace.id, actor: owner)

      accepted = Accounts.accept_invitation!(invitation)

      accepted = Accounts.get_invitation_by_token!(accepted.token, load: [:is_accepted])

      assert accepted.is_accepted == true
    end

    test "is_accepted returns false for non-accepted invitations" do
      owner = generate(user())
      invitee_email = unique_user_email()
      workspace = generate(workspace([], actor: owner))

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      invitation = Accounts.get_invitation_by_token!(invitation.token, load: [:is_accepted])

      assert invitation.is_accepted == false
    end
  end
end
