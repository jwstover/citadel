defmodule Citadel.Workers.SendConfirmationEmailWorker do
  @moduledoc """
  Oban worker for sending email confirmation emails.

  This worker processes confirmation email jobs asynchronously, ensuring
  user registration succeeds even if email delivery fails temporarily.
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
        Logger.warning("User #{user_id} not found for email confirmation")
        :ok

      {:ok, user} ->
        if user.confirmed_at do
          Logger.info("User #{user_id} already confirmed, skipping email")
          :ok
        else
          send_email(user, token)
        end

      {:error, _} ->
        Logger.warning("Failed to load user #{user_id}")
        :ok
    end
  end

  defp send_email(user, token) do
    confirm_url = build_confirm_url(token)

    user
    |> Emails.confirmation_email(confirm_url)
    |> Mailer.deliver()
    |> case do
      {:ok, _} ->
        Logger.info("Sent confirmation email to #{user.email}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to send confirmation email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_confirm_url(token) do
    CitadelWeb.Endpoint.url() <> "/confirm_new_user/#{token}"
  end
end
