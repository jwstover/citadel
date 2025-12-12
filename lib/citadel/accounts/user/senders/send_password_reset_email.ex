defmodule Citadel.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email via Oban background job.

  This sender enqueues an Oban job to send the email asynchronously,
  ensuring the password reset request completes even if email delivery
  is slow or fails temporarily.
  """

  use AshAuthentication.Sender

  alias Citadel.Workers.SendPasswordResetEmailWorker

  @impl AshAuthentication.Sender
  def send(user, token, _opts) do
    %{user_id: user.id, token: token}
    |> SendPasswordResetEmailWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, _reason} -> :ok
    end
  end
end
