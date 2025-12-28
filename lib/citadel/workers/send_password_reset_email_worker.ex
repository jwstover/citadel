defmodule Citadel.Workers.SendPasswordResetEmailWorker do
  @moduledoc """
  Oban worker for sending password reset emails.

  This worker processes password reset email jobs asynchronously, ensuring
  the password reset flow succeeds even if email delivery fails temporarily.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5

  require Logger

  alias Citadel.Accounts.User
  alias Citadel.Emails
  alias Citadel.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "token" => token}}) do
    case Ash.get(User, user_id, authorize?: false) do
      {:ok, nil} ->
        Logger.warning("User #{user_id} not found for password reset")
        :ok

      {:ok, user} ->
        send_email(user, token)

      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} ->
        Logger.warning("User #{user_id} not found for password reset")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to load user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp send_email(user, token) do
    reset_url = build_reset_url(token)

    user
    |> Emails.password_reset_email(reset_url)
    |> Mailer.deliver()
    |> case do
      {:ok, _} ->
        Logger.info("Sent password reset email to #{user.email}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to send password reset email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_reset_url(token) do
    CitadelWeb.Endpoint.url() <> "/password-reset/#{token}"
  end
end
