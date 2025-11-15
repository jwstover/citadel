defmodule Citadel.Accounts.WorkspaceInvitationTest do
  use Citadel.DataCase, async: true

  alias Citadel.Accounts

  describe "create_invitation/3" do
    test "creates an invitation with valid email and workspace" do
      owner = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

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
      owner = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      # Token should be a long random string
      assert String.length(invitation.token) > 30
      assert invitation.token =~ ~r/^[A-Za-z0-9_-]+$/
    end

    test "tokens are unique across invitations" do
      owner = create_user()
      email1 = unique_user_email()
      email2 = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation1 = Accounts.create_invitation!(email1, workspace.id, actor: owner)
      invitation2 = Accounts.create_invitation!(email2, workspace.id, actor: owner)

      assert invitation1.token != invitation2.token
    end

    test "sets expires_at to 7 days from now" do
      owner = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      # Check that expires_at is approximately 7 days from now
      seven_days_from_now = DateTime.add(DateTime.utc_now(), 7, :day)
      diff = DateTime.diff(invitation.expires_at, seven_days_from_now, :second)

      # Allow 5 second tolerance
      assert abs(diff) < 5
    end

    test "workspace member can create invitation" do
      owner = create_user()
      member = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      # Add member to workspace
      Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      # Member can create invitation
      assert invitation =
               Accounts.create_invitation!(invitee_email, workspace.id, actor: member)

      assert invitation.invited_by_id == member.id
    end

    test "raises error when non-member tries to create invitation" do
      owner = create_user()
      non_member = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      # Non-member should not be able to create invitation
      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.create_invitation!(invitee_email, workspace.id, actor: non_member)
      end
    end
  end

  describe "list_workspace_invitations/1" do
    test "workspace members can list invitations for their workspace" do
      owner = create_user()
      email1 = unique_user_email()
      email2 = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

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
      owner = create_user()
      non_member = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      _invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      # Non-member should not see invitations
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
      owner = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      # Anyone (even without actor) can get invitation by token
      fetched = Accounts.get_invitation_by_token!(invitation.token)

      assert fetched.id == invitation.id
      assert to_string(fetched.email) == invitee_email
    end
  end

  describe "accept_invitation/2" do
    test "accepts invitation and creates workspace membership" do
      owner = create_user()
      invitee = create_user()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(invitee.email, workspace.id, actor: owner)

      # Accept the invitation
      accepted = Accounts.accept_invitation!(invitation)

      assert not is_nil(accepted.accepted_at)

      # Verify membership was created
      memberships =
        Accounts.list_workspace_members!(actor: invitee, query: [filter: [user_id: invitee.id]])

      assert length(memberships) == 1
      membership = hd(memberships)
      assert membership.workspace_id == workspace.id
      assert membership.user_id == invitee.id
    end

    test "raises error when accepting expired invitation" do
      owner = create_user()
      invitee = create_user()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      # Create invitation with expired date
      invitation =
        Accounts.create_invitation!(invitee.email, workspace.id, actor: owner)
        |> Ash.Changeset.for_update(:update, %{
          expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
        })
        |> Ash.update!(authorize?: false)

      # Trying to accept expired invitation should fail
      assert_raise Ash.Error.Invalid, fn ->
        Accounts.accept_invitation!(invitation)
      end
    end

    test "raises error when accepting already accepted invitation" do
      owner = create_user()
      invitee = create_user()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(invitee.email, workspace.id, actor: owner)

      # Accept the invitation once
      Accounts.accept_invitation!(invitation)

      # Reload the invitation
      invitation = Accounts.get_invitation_by_token!(invitation.token)

      # Trying to accept again should fail
      assert_raise Ash.Error.Invalid, fn ->
        Accounts.accept_invitation!(invitation)
      end
    end

    test "raises error when user email doesn't exist" do
      owner = create_user()
      non_existent_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(non_existent_email, workspace.id, actor: owner)

      # Trying to accept with non-existent user should fail
      assert_raise Ash.Error.Unknown, fn ->
        Accounts.accept_invitation!(invitation)
      end
    end
  end

  describe "revoke_invitation/2" do
    test "workspace owner can revoke invitation" do
      owner = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      assert :ok = Accounts.revoke_invitation!(invitation, actor: owner)

      # Verify invitation is gone
      assert_raise Ash.Error.Invalid, fn ->
        Accounts.get_invitation_by_token!(invitation.token)
      end
    end

    test "raises error when non-owner tries to revoke invitation" do
      owner = create_user()
      member = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      # Add member to workspace
      Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      # Member should not be able to revoke invitation
      assert_raise Ash.Error.Forbidden, fn ->
        Accounts.revoke_invitation!(invitation, actor: member)
      end
    end
  end

  describe "calculations" do
    test "is_expired returns true for expired invitations" do
      owner = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      # Create invitation with expired date
      invitation =
        Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)
        |> Ash.Changeset.for_update(:update, %{
          expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
        })
        |> Ash.update!(authorize?: false)

      # Load calculation
      invitation = Accounts.get_invitation_by_token!(invitation.token, load: [:is_expired])

      assert invitation.is_expired == true
    end

    test "is_expired returns false for non-expired invitations" do
      owner = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      # Load calculation
      invitation = Accounts.get_invitation_by_token!(invitation.token, load: [:is_expired])

      assert invitation.is_expired == false
    end

    test "is_accepted returns true for accepted invitations" do
      owner = create_user()
      invitee = create_user()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(invitee.email, workspace.id, actor: owner)

      # Accept invitation
      accepted = Accounts.accept_invitation!(invitation)

      # Load calculation
      accepted = Accounts.get_invitation_by_token!(accepted.token, load: [:is_accepted])

      assert accepted.is_accepted == true
    end

    test "is_accepted returns false for non-accepted invitations" do
      owner = create_user()
      invitee_email = unique_user_email()

      workspace =
        Accounts.create_workspace!(
          "Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      # Load calculation
      invitation = Accounts.get_invitation_by_token!(invitation.token, load: [:is_accepted])

      assert invitation.is_accepted == false
    end
  end
end
