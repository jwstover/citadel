defmodule Citadel.Workers.SendInvitationEmailWorker do
  @moduledoc """
  Oban worker for sending workspace invitation emails.

  This worker processes invitation email jobs asynchronously, ensuring
  invitation creation succeeds even if email delivery fails temporarily.
  """
  use Oban.Worker,
    queue: :invitations,
    max_attempts: 5,
    unique: [period: 300, keys: [:invitation_id]]

  require Logger

  alias Citadel.Accounts.WorkspaceInvitation
  alias Citadel.Emails
  alias Citadel.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invitation_id" => invitation_id}}) do
    case load_invitation(invitation_id) do
      {:ok, invitation} ->
        send_email(invitation)

      {:error, :not_found} ->
        Logger.warning("Invitation #{invitation_id} not found, skipping email")
        :ok

      {:error, :already_accepted} ->
        Logger.info("Invitation #{invitation_id} already accepted, skipping email")
        :ok
    end
  end

  defp load_invitation(invitation_id) do
    case Ash.get(WorkspaceInvitation, invitation_id,
           load: [:workspace, :invited_by],
           authorize?: false
         ) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, invitation} ->
        if invitation.accepted_at do
          {:error, :already_accepted}
        else
          {:ok, invitation}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp send_email(invitation) do
    accept_url = build_accept_url(invitation.token)

    invitation
    |> Emails.workspace_invitation_email(accept_url)
    |> Mailer.deliver()
    |> case do
      {:ok, _} ->
        Logger.info(
          "Sent invitation email to #{invitation.email} for workspace #{invitation.workspace.name}"
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to send invitation email to #{invitation.email}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_accept_url(token) do
    CitadelWeb.Endpoint.url() <> "/invitations/#{token}"
  end
end
