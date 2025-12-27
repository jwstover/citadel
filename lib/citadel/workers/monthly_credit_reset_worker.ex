defmodule Citadel.Workers.MonthlyCreditResetWorker do
  @moduledoc """
  Oban cron worker that resets monthly credits for all organizations.

  Runs on the 1st of each month at midnight UTC via Oban cron:

      {"0 0 1 * *", Citadel.Workers.MonthlyCreditResetWorker}

  Uses subscription period tracking for idempotency - only resets credits
  if the current date is >= the subscription's `current_period_end`.

  ## Idempotency

  The worker is idempotent because:
  1. It only processes subscriptions where `current_period_end <= today`
  2. After processing, it updates `current_period_end` to the next month
  3. Running the job multiple times in a day won't double-credit

  ## Credit Amounts

  Credits are allocated based on subscription tier:
  - Free: 500 credits/month
  - Pro: 10,000 credits/month
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Ash.Query
  require Logger

  alias Citadel.Billing
  alias Citadel.Billing.{Plan, Subscription}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    results =
      subscriptions_needing_reset(now)
      |> Enum.map(&reset_credits_for_subscription(&1, now))

    failures = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(failures) do
      :ok
    else
      {:error, "#{length(failures)} subscription(s) failed to reset credits"}
    end
  end

  defp subscriptions_needing_reset(now) do
    Subscription
    |> Ash.Query.filter(
      status == :active and
        (is_nil(current_period_end) or current_period_end <= ^now)
    )
    |> Ash.read!(authorize?: false)
  end

  defp reset_credits_for_subscription(subscription, now) do
    credits = Plan.monthly_credits(subscription.tier)
    next_period_start = DateTime.truncate(now, :second)
    next_period_end = next_month(now)

    case Citadel.Repo.transaction(fn ->
           Billing.add_credits!(
             subscription.organization_id,
             credits,
             "Monthly credit allocation (#{subscription.tier} tier)",
             %{transaction_type: :bonus},
             authorize?: false
           )

           subscription
           |> Ash.Changeset.for_update(:update, %{
             current_period_start: next_period_start,
             current_period_end: next_period_end
           })
           |> Ash.update!(authorize?: false)
         end) do
      {:ok, _} ->
        Logger.info(
          "Reset #{credits} credits for organization #{subscription.organization_id} " <>
            "(#{subscription.tier} tier). Next reset: #{next_period_end}"
        )

        {:ok, subscription.organization_id}

      {:error, reason} ->
        Logger.error(
          "Failed to reset credits for organization #{subscription.organization_id}: " <>
            "#{inspect(reason)}"
        )

        {:error, {subscription.organization_id, reason}}
    end
  end

  defp next_month(datetime) do
    date = DateTime.to_date(datetime)

    next_date =
      date
      |> Date.add(Date.days_in_month(date))
      |> Date.beginning_of_month()

    DateTime.new!(next_date, ~T[00:00:00], "Etc/UTC")
  end
end
