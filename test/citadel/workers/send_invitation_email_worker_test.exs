defmodule Citadel.Workers.SendInvitationEmailWorkerTest do
  use Citadel.DataCase, async: true
  use Oban.Testing, repo: Citadel.Repo

  import Swoosh.TestAssertions

  alias Citadel.Accounts
  alias Citadel.Workers.SendInvitationEmailWorker

  describe "perform/1" do
    test "sends invitation email successfully" do
      owner = create_user()

      workspace =
        Accounts.create_workspace!("Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitee_email = unique_user_email()
      invitation = Accounts.create_invitation!(invitee_email, workspace.id, actor: owner)

      assert :ok = perform_job(SendInvitationEmailWorker, %{invitation_id: invitation.id})

      assert_email_sent(fn email ->
        assert email.to == [{"", invitee_email}]
        assert email.subject =~ workspace.name
      end)
    end

    test "email contains acceptance link with token" do
      owner = create_user()

      workspace =
        Accounts.create_workspace!("Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(unique_user_email(), workspace.id, actor: owner)

      assert :ok = perform_job(SendInvitationEmailWorker, %{invitation_id: invitation.id})

      assert_email_sent(fn email ->
        assert email.text_body =~ "/invitations/#{invitation.token}"
        assert email.html_body =~ "/invitations/#{invitation.token}"
      end)
    end

    test "succeeds when invitation not found" do
      assert :ok = perform_job(SendInvitationEmailWorker, %{invitation_id: Ash.UUID.generate()})
      assert_no_email_sent()
    end

    test "succeeds when invitation already accepted" do
      owner = create_user()
      invitee = create_user()

      workspace =
        Accounts.create_workspace!("Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation = Accounts.create_invitation!(invitee.email, workspace.id, actor: owner)

      # Accept the invitation
      Accounts.accept_invitation!(invitation)

      # Clear any emails sent during the setup
      Swoosh.TestAssertions.refute_email_sent()

      # Worker should succeed but not send email
      assert :ok = perform_job(SendInvitationEmailWorker, %{invitation_id: invitation.id})
      assert_no_email_sent()
    end
  end
end
