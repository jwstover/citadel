defmodule Citadel.Accounts.WorkspaceInvitationEmailTest do
  use Citadel.DataCase, async: true

  alias Citadel.Accounts
  alias Citadel.Workers.SendInvitationEmailWorker

  describe "invitation creation enqueues email job" do
    test "enqueues SendInvitationEmailWorker when invitation is created" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

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
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

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
