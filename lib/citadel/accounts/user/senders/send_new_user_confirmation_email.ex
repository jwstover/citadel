defmodule Citadel.Accounts.User.Senders.SendNewUserConfirmationEmail do
  @moduledoc """
  Sends an email confirmation via Oban background job.

  This sender enqueues an Oban job to send the email asynchronously,
  ensuring user registration completes even if email delivery
  is slow or fails temporarily.
  """

  use AshAuthentication.Sender

  alias Citadel.Workers.SendConfirmationEmailWorker

  @impl AshAuthentication.Sender
  def send(user, token, _opts) do
    %{user_id: user.id, token: token}
    |> SendConfirmationEmailWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, _reason} -> :ok
    end
  end
end
