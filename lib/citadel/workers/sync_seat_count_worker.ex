defmodule Citadel.Workers.SyncSeatCountWorker do
  @moduledoc """
  Oban worker that syncs organization seat count to Stripe.

  This worker is triggered when OrganizationMembership changes (join/leave).
  It uses Oban's unique job feature to deduplicate rapid membership changes,
  ensuring we only make one Stripe API call per organization within a 60-second window.

  ## How it works

  1. When a member is added or removed, an `EnqueueSeatSync` change triggers this worker
  2. The worker counts the current organization members
  3. If the count differs from the subscription's seat_count, it updates Stripe
  4. The local subscription record is updated to match

  ## Error handling

  - If no subscription exists, the job succeeds silently (free tier with no Stripe sub)
  - If Stripe API fails, the job is retried up to 3 times
  - After max retries, the job moves to the dead queue for manual review
  """
  use Oban.Worker,
    queue: :billing,
    max_attempts: 3,
    unique: [
      period: 60,
      states: :incomplete
    ]

  require Logger
  require Ash.Query

  alias Citadel.Accounts.OrganizationMembership
  alias Citadel.Billing
  alias Citadel.Billing.Stripe, as: StripeService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => org_id}}) do
    with {:ok, subscription} <- get_subscription(org_id),
         {:ok, member_count} <- count_members(org_id),
         :ok <- sync_if_needed(subscription, member_count) do
      :ok
    else
      {:error, :no_subscription} ->
        Logger.debug("No subscription for org #{org_id}, skipping seat sync")
        :ok

      {:error, :no_stripe_subscription} ->
        Logger.debug("No Stripe subscription for org #{org_id}, skipping seat sync")
        :ok

      {:error, error} ->
        Logger.error("Failed to sync seats for org #{org_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp get_subscription(org_id) do
    case Billing.get_subscription_by_organization(org_id, authorize?: false) do
      {:ok, subscription} -> {:ok, subscription}
      {:error, _} -> {:error, :no_subscription}
    end
  end

  defp count_members(org_id) do
    count =
      OrganizationMembership
      |> Ash.Query.filter(organization_id == ^org_id)
      |> Ash.count!(authorize?: false)

    {:ok, count}
  end

  defp sync_if_needed(subscription, member_count) do
    cond do
      is_nil(subscription.stripe_subscription_id) ->
        {:error, :no_stripe_subscription}

      subscription.seat_count == member_count ->
        Logger.debug("Seat count unchanged at #{member_count}, skipping sync")
        :ok

      true ->
        sync_seats(subscription, member_count)
    end
  end

  defp sync_seats(subscription, member_count) do
    Logger.info(
      "Syncing seat count for org #{subscription.organization_id}: " <>
        "#{subscription.seat_count} -> #{member_count}"
    )

    case StripeService.update_seats(
           subscription.stripe_subscription_id,
           member_count,
           subscription.tier,
           subscription.billing_period
         ) do
      {:ok, _} ->
        update_local_seat_count(subscription, member_count)

      {:error, error} ->
        {:error, error}
    end
  end

  defp update_local_seat_count(subscription, member_count) do
    case Billing.update_subscription(
           subscription,
           %{seat_count: member_count},
           authorize?: false
         ) do
      {:ok, _} ->
        Logger.info("Updated local seat count to #{member_count}")
        :ok

      {:error, error} ->
        Logger.error("Failed to update local seat count: #{inspect(error)}")
        {:error, error}
    end
  end
end
