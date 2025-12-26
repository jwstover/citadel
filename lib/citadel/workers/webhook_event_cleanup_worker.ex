defmodule Citadel.Workers.WebhookEventCleanupWorker do
  @moduledoc """
  Oban cron worker that cleans up old processed webhook events.

  Runs daily at 3 AM UTC to remove events older than 30 days.
  We keep processed events for 30 days to handle any delayed
  Stripe retries or debugging needs.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Logger

  alias Citadel.Billing

  @retention_days 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Billing.cleanup_old_webhook_events(@retention_days, authorize?: false) do
      {:ok, count} when count > 0 ->
        Logger.info("Cleaned up #{count} processed webhook events older than #{@retention_days} days")

      {:ok, 0} ->
        Logger.debug("No old webhook events to clean up")

      {:error, reason} ->
        Logger.error("Failed to cleanup old webhook events: #{inspect(reason)}")
    end

    :ok
  end
end
