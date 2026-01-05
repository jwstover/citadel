defmodule Citadel.Billing.Stripe do
  @moduledoc """
  Service module for Stripe API interactions.

  Handles customer creation, checkout sessions, subscription management,
  and billing portal access.
  """

  require Logger

  alias Citadel.Billing.Plan

  @type organization :: Citadel.Accounts.Organization.t()
  @type subscription :: Citadel.Billing.Subscription.t()
  @type billing_period :: :monthly | :annual

  @doc """
  Creates a Stripe customer for an organization.

  The customer is created with the organization's name and ID stored in metadata
  for webhook correlation.

  ## Examples

      iex> create_customer(organization)
      {:ok, "cus_xxx"}

      iex> create_customer(organization)
      {:error, %Stripe.Error{}}
  """
  @spec create_customer(organization()) :: {:ok, String.t()} | {:error, term()}
  def create_customer(organization) do
    params = %{
      name: organization.name,
      metadata: %{
        organization_id: organization.id
      }
    }

    case Stripe.Customer.create(params) do
      {:ok, %Stripe.Customer{id: customer_id}} ->
        Logger.info("Created Stripe customer #{customer_id} for organization #{organization.id}")
        {:ok, customer_id}

      {:error, error} ->
        Logger.error(
          "Failed to create Stripe customer for organization #{organization.id}: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  @doc """
  Creates a Stripe checkout session for upgrading to a paid tier.

  The checkout session includes the base subscription price and per-seat pricing
  for additional members. The organization ID is stored in metadata for webhook
  correlation.

  ## Parameters

    - `subscription` - The current subscription to upgrade
    - `tier` - The tier to upgrade to (e.g., `:pro`)
    - `billing_period` - Either `:monthly` or `:annual`
    - `seat_count` - Number of seats to include
    - `success_url` - URL to redirect to after successful payment
    - `cancel_url` - URL to redirect to if payment is cancelled

  ## Examples

      iex> create_checkout_session(subscription, :pro, :monthly, 3, "https://...", "https://...")
      {:ok, "https://checkout.stripe.com/..."}
  """
  @spec create_checkout_session(
          subscription(),
          atom(),
          billing_period(),
          integer(),
          String.t(),
          String.t()
        ) ::
          {:ok, String.t()} | {:error, term()}
  def create_checkout_session(
        subscription,
        tier,
        billing_period,
        seat_count,
        success_url,
        cancel_url
      ) do
    base_price_id = Plan.stripe_price_id(tier, billing_period)
    seat_price_id = Plan.stripe_seat_price_id(tier, billing_period)

    if is_nil(base_price_id) do
      {:error, :missing_stripe_price_id}
    else
      line_items = build_line_items(base_price_id, seat_price_id, seat_count)

      params = %{
        mode: "subscription",
        customer: subscription.stripe_customer_id,
        success_url: success_url,
        cancel_url: cancel_url,
        line_items: line_items,
        subscription_data: %{
          metadata: %{
            organization_id: subscription.organization_id,
            billing_period: to_string(billing_period)
          }
        },
        metadata: %{
          organization_id: subscription.organization_id
        }
      }

      case Stripe.Checkout.Session.create(params) do
        {:ok, %Stripe.Checkout.Session{url: url}} ->
          Logger.info("Created checkout session for organization #{subscription.organization_id}")

          {:ok, url}

        {:error, error} ->
          Logger.error(
            "Failed to create checkout session for organization #{subscription.organization_id}: #{inspect(error)}"
          )

          {:error, error}
      end
    end
  end

  defp build_line_items(base_price_id, seat_price_id, seat_count) do
    base_item = %{price: base_price_id, quantity: 1}

    if seat_price_id && seat_count > 1 do
      # Additional seats beyond the owner (included in base)
      additional_seats = seat_count - 1
      [base_item, %{price: seat_price_id, quantity: additional_seats}]
    else
      [base_item]
    end
  end

  @doc """
  Updates the seat quantity on a Stripe subscription.

  This is called when organization membership changes to sync the seat count
  with Stripe for accurate billing.

  ## Examples

      iex> update_seats("sub_xxx", 5, :pro, :monthly)
      {:ok, %Stripe.Subscription{}}
  """
  @spec update_seats(String.t(), integer(), atom(), billing_period()) ::
          {:ok, term()} | {:error, term()}
  def update_seats(stripe_subscription_id, seat_count, tier, billing_period) do
    seat_price_id = Plan.stripe_seat_price_id(tier, billing_period)

    if is_nil(seat_price_id) do
      Logger.warning("No seat price ID configured, skipping seat update")
      {:ok, :no_seat_pricing}
    else
      case Stripe.Subscription.retrieve(stripe_subscription_id) do
        {:ok, subscription} ->
          update_subscription_seats(subscription, seat_price_id, seat_count)

        {:error, error} ->
          Logger.error(
            "Failed to retrieve subscription #{stripe_subscription_id}: #{inspect(error)}"
          )

          {:error, error}
      end
    end
  end

  defp update_subscription_seats(subscription, seat_price_id, seat_count) do
    # Find the seat item in the subscription
    seat_item = find_seat_item(subscription.items.data, seat_price_id)
    additional_seats = max(seat_count - 1, 0)

    items =
      case seat_item do
        nil when additional_seats > 0 ->
          # Add new seat item
          [%{price: seat_price_id, quantity: additional_seats}]

        nil ->
          # No seats to add
          []

        %{id: item_id} when additional_seats > 0 ->
          # Update existing seat item
          [%{id: item_id, quantity: additional_seats}]

        %{id: item_id} ->
          # Remove seat item (no additional seats)
          [%{id: item_id, deleted: true}]
      end

    if items == [] do
      {:ok, subscription}
    else
      case Stripe.Subscription.update(subscription.id, %{items: items}) do
        {:ok, updated} ->
          Logger.info("Updated seats for subscription #{subscription.id} to #{seat_count}")
          {:ok, updated}

        {:error, error} ->
          Logger.error(
            "Failed to update seats for subscription #{subscription.id}: #{inspect(error)}"
          )

          {:error, error}
      end
    end
  end

  defp find_seat_item(items, seat_price_id) do
    Enum.find(items, fn item ->
      item.price.id == seat_price_id
    end)
  end

  @doc """
  Creates a billing portal session for the customer.

  The billing portal allows customers to manage their subscription, update
  payment methods, and view invoices.

  ## Examples

      iex> create_portal_session("cus_xxx", "https://app.citadel.com/settings")
      {:ok, "https://billing.stripe.com/..."}
  """
  @spec create_portal_session(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def create_portal_session(stripe_customer_id, return_url) do
    params = %{
      customer: stripe_customer_id,
      return_url: return_url
    }

    case Stripe.BillingPortal.Session.create(params) do
      {:ok, %{url: url}} ->
        {:ok, url}

      {:error, error} ->
        Logger.error(
          "Failed to create portal session for customer #{stripe_customer_id}: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  @doc """
  Cancels a Stripe subscription.

  The subscription is cancelled at the end of the current billing period
  to avoid prorating.

  ## Examples

      iex> cancel_subscription("sub_xxx")
      {:ok, %Stripe.Subscription{}}
  """
  @spec cancel_subscription(String.t()) :: {:ok, term()} | {:error, term()}
  def cancel_subscription(stripe_subscription_id) do
    case Stripe.Subscription.update(stripe_subscription_id, %{cancel_at_period_end: true}) do
      {:ok, subscription} ->
        Logger.info("Cancelled subscription #{stripe_subscription_id}")
        {:ok, subscription}

      {:error, error} ->
        Logger.error("Failed to cancel subscription #{stripe_subscription_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Constructs and verifies a Stripe webhook event from the raw payload and signature.

  ## Examples

      iex> construct_event(payload, signature)
      {:ok, %Stripe.Event{}}

      iex> construct_event(invalid_payload, signature)
      {:error, "Signature verification failed"}
  """
  @spec construct_event(String.t(), String.t()) :: {:ok, Stripe.Event.t()} | {:error, term()}
  def construct_event(payload, signature) do
    signing_secret = Application.get_env(:stripity_stripe, :signing_secret)

    case Stripe.Webhook.construct_event(payload, signature, signing_secret) do
      {:ok, event} ->
        {:ok, event}

      {:error, reason} ->
        Logger.warning("Stripe webhook signature verification failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
