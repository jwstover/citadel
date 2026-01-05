defmodule Citadel.Accounts.Organization.Changes.CreateStripeCustomer do
  @moduledoc """
  Creates a Stripe customer and subscription for a newly created organization.

  This change runs in `after_transaction` to ensure:
  1. The organization is fully created and committed
  2. If Stripe fails, the organization creation is not rolled back
  3. The subscription can be created with the organization ID

  The workflow is:
  1. Create a free-tier subscription for the organization
  2. Create a Stripe customer via the Stripe API
  3. Update the subscription with the Stripe customer ID

  If Stripe customer creation fails, the organization and subscription are still
  created successfully - the Stripe customer can be created later when the user
  attempts to upgrade.
  """
  use Ash.Resource.Change

  require Logger

  alias Citadel.Billing
  alias Citadel.Billing.Plan
  alias Citadel.Billing.Stripe, as: StripeService

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, organization} ->
        create_subscription_and_customer(organization)
        {:ok, organization}

      _changeset, {:error, error} ->
        {:error, error}
    end)
  end

  defp create_subscription_and_customer(organization) do
    with {:ok, subscription} <- create_subscription(organization),
         {:ok, customer_id} <- create_stripe_customer(organization) do
      update_subscription_with_customer(subscription, customer_id)
    else
      {:error, :stripe_customer_creation_failed} ->
        Logger.warning(
          "Stripe customer creation failed for organization #{organization.id}, " <>
            "subscription created without customer ID"
        )

        :ok

      {:error, error} ->
        Logger.error(
          "Failed to create subscription for organization #{organization.id}: #{inspect(error)}"
        )

        :ok
    end
  end

  defp create_subscription(organization) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    period_end = DateTime.add(now, 30, :day)

    Billing.create_subscription(
      organization.id,
      Plan.default_tier(),
      %{
        current_period_start: now,
        current_period_end: period_end
      },
      authorize?: false
    )
  end

  defp create_stripe_customer(organization) do
    if Application.get_env(:citadel, :skip_stripe_in_tests, false) do
      {:error, :stripe_customer_creation_failed}
    else
      case StripeService.create_customer(organization) do
        {:ok, customer_id} ->
          {:ok, customer_id}

        {:error, _error} ->
          {:error, :stripe_customer_creation_failed}
      end
    end
  end

  defp update_subscription_with_customer(subscription, customer_id) do
    case Billing.update_subscription(
           subscription,
           %{stripe_customer_id: customer_id},
           authorize?: false
         ) do
      {:ok, _subscription} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to update subscription with customer ID: #{inspect(error)}")
        :ok
    end
  end
end
