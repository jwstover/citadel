defmodule Citadel.Accounts.WorkspaceInvitationEmailTest do
  use Citadel.DataCase, async: true
  use Oban.Testing, repo: Citadel.Repo

  alias Citadel.Accounts
  alias Citadel.Workers.SendInvitationEmailWorker

  describe "invitation creation enqueues email job" do
    test "enqueues SendInvitationEmailWorker when invitation is created" do
      owner = create_user()

      workspace =
        Accounts.create_workspace!("Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation =
        Accounts.create_invitation!(
          unique_user_email(),
          workspace.id,
          actor: owner
        )

      assert_enqueued(
        worker: SendInvitationEmailWorker,
        args: %{invitation_id: invitation.id}
      )
    end

    test "enqueues job with correct queue" do
      owner = create_user()

      workspace =
        Accounts.create_workspace!("Test Workspace #{System.unique_integer([:positive])}",
          actor: owner
        )

      invitation =
        Accounts.create_invitation!(
          unique_user_email(),
          workspace.id,
          actor: owner
        )

      assert_enqueued(
        worker: SendInvitationEmailWorker,
        args: %{invitation_id: invitation.id},
        queue: :invitations
      )
    end
  end
end
