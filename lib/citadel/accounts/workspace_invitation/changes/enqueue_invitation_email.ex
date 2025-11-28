defmodule Citadel.Accounts.WorkspaceInvitation.Changes.EnqueueInvitationEmail do
  @moduledoc """
  Enqueues an Oban job to send the invitation email after successful creation.

  The email is sent asynchronously to avoid blocking the invitation creation.
  If the job fails to enqueue, the invitation still succeeds (graceful degradation).
  """
  use Ash.Resource.Change

  require Logger

  alias Citadel.Workers.SendInvitationEmailWorker

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, invitation ->
      case enqueue_email_job(invitation) do
        {:ok, _job} ->
          {:ok, invitation}

        {:error, reason} ->
          Logger.error("Failed to enqueue invitation email job: #{inspect(reason)}")
          {:ok, invitation}
      end
    end)
  end

  defp enqueue_email_job(invitation) do
    %{invitation_id: invitation.id}
    |> SendInvitationEmailWorker.new()
    |> Oban.insert()
  end
end
