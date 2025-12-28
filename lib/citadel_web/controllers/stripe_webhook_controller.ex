defmodule CitadelWeb.StripeWebhookController do
  @moduledoc """
  Handles Stripe webhook events.

  This controller receives webhook events from Stripe, verifies their signatures,
  and processes them appropriately.

  ## Events Handled

  - `checkout.session.completed` - Activates Pro subscription after successful payment
  - `invoice.paid` - Updates subscription period dates after successful payment
  - `invoice.payment_failed` - Sets subscription status to past_due
  - `customer.subscription.deleted` - Cancels subscription when deleted in Stripe
  - `customer.subscription.updated` - Syncs subscription changes from Stripe
  """

  use CitadelWeb, :controller

  require Logger

  alias Citadel.Billing
  alias Citadel.Billing.Stripe, as: StripeService

  @doc """
  Main webhook endpoint - verifies signature and routes events.
  """
  def handle(conn, _params) do
    with {:ok, raw_body} <- get_raw_body(conn),
         {:ok, signature} <- get_stripe_signature(conn),
         {:ok, event} <- StripeService.construct_event(raw_body, signature),
         :ok <- check_and_record_event(event) do
      handle_event(event)
      send_resp(conn, 200, "")
    else
      {:error, :missing_raw_body} ->
        Logger.warning("Stripe webhook received without raw body")
        send_resp(conn, 400, "Missing request body")

      {:error, :missing_signature} ->
        Logger.warning("Stripe webhook received without signature")
        send_resp(conn, 400, "Missing Stripe signature")

      {:error, :already_processed} ->
        Logger.debug("Stripe webhook event already processed, acknowledging")
        send_resp(conn, 200, "")

      {:error, reason} ->
        Logger.warning("Stripe webhook verification failed: #{inspect(reason)}")
        send_resp(conn, 400, "Webhook verification failed")
    end
  end

  defp check_and_record_event(%Stripe.Event{id: event_id, type: event_type}) do
    case Billing.event_processed?(event_id, authorize?: false) do
      {:ok, true} ->
        Logger.info("Duplicate webhook event detected: #{event_id}")
        {:error, :already_processed}

      {:ok, false} ->
        Billing.record_webhook_event!(event_id, event_type, authorize?: false)
        :ok

      {:error, reason} ->
        Logger.error("Failed to check/record webhook event: #{inspect(reason)}")
        :ok
    end
  end

  defp get_raw_body(conn) do
    case conn.assigns[:raw_body] do
      nil -> {:error, :missing_raw_body}
      "" -> {:error, :missing_raw_body}
      body -> {:ok, body}
    end
  end

  defp get_stripe_signature(conn) do
    case Plug.Conn.get_req_header(conn, "stripe-signature") do
      [signature] -> {:ok, signature}
      _ -> {:error, :missing_signature}
    end
  end

  defp handle_event(%Stripe.Event{type: "checkout.session.completed", data: %{object: session}}) do
    Logger.info("Processing checkout.session.completed for session #{session.id}")

    with {:ok, org_id} <- get_organization_id(session),
         {:ok, subscription} <- get_subscription_by_org(org_id),
         {:ok, stripe_sub} <- get_stripe_subscription(session.subscription) do
      billing_period = get_billing_period(session)
      {period_start, period_end} = get_period_from_subscription(stripe_sub)

      Billing.update_subscription!(
        subscription,
        %{
          tier: :pro,
          status: :active,
          billing_period: billing_period,
          stripe_subscription_id: stripe_sub.id,
          stripe_customer_id: session.customer,
          current_period_start: period_start,
          current_period_end: period_end
        },
        authorize?: false
      )

      Logger.info("Activated Pro subscription for organization #{org_id}")
    else
      error ->
        Logger.error("Failed to process checkout.session.completed: #{inspect(error)}")
    end
  end

  defp handle_event(%Stripe.Event{type: "invoice.paid", data: %{object: invoice}}) do
    Logger.info("Processing invoice.paid for invoice #{invoice.id}")

    with {:ok, subscription_id} <- get_subscription_id_from_invoice(invoice),
         {:ok, stripe_sub} <- get_stripe_subscription(subscription_id),
         {:ok, subscription} <- get_subscription_by_stripe_id(stripe_sub.id),
         :ok <- validate_customer_ownership(subscription, invoice.customer) do
      {period_start, period_end} = get_period_from_subscription(stripe_sub)

      Billing.update_subscription!(
        subscription,
        %{
          status: :active,
          current_period_start: period_start,
          current_period_end: period_end
        },
        authorize?: false
      )

      Logger.info("Updated period for subscription #{subscription.id}")
    else
      {:error, :no_subscription_id} ->
        Logger.debug("Invoice #{invoice.id} has no subscription, skipping")

      {:error, :customer_mismatch} ->
        Logger.warning("Rejecting invoice.paid event due to customer mismatch")

      error ->
        Logger.error("Failed to process invoice.paid: #{inspect(error)}")
    end
  end

  defp handle_event(%Stripe.Event{type: "invoice.payment_failed", data: %{object: invoice}}) do
    Logger.info("Processing invoice.payment_failed for invoice #{invoice.id}")

    with {:ok, subscription_id} <- get_subscription_id_from_invoice(invoice),
         {:ok, subscription} <- get_subscription_by_stripe_sub_id(subscription_id),
         :ok <- validate_customer_ownership(subscription, invoice.customer) do
      Billing.update_subscription!(
        subscription,
        %{status: :past_due},
        authorize?: false
      )

      Logger.info("Marked subscription #{subscription.id} as past_due")
    else
      {:error, :no_subscription_id} ->
        Logger.debug("Invoice #{invoice.id} has no subscription, skipping")

      {:error, :customer_mismatch} ->
        Logger.warning("Rejecting invoice.payment_failed event due to customer mismatch")

      error ->
        Logger.error("Failed to process invoice.payment_failed: #{inspect(error)}")
    end
  end

  defp handle_event(%Stripe.Event{
         type: "customer.subscription.deleted",
         data: %{object: stripe_sub}
       }) do
    Logger.info("Processing customer.subscription.deleted for subscription #{stripe_sub.id}")

    with {:ok, subscription} <- get_subscription_by_stripe_id(stripe_sub.id),
         :ok <- validate_customer_ownership(subscription, stripe_sub.customer) do
      Billing.update_subscription!(
        subscription,
        %{status: :canceled},
        authorize?: false
      )

      Logger.info("Cancelled subscription #{subscription.id}")
    else
      {:error, :customer_mismatch} ->
        Logger.warning("Rejecting customer.subscription.deleted event due to customer mismatch")

      error ->
        Logger.error("Failed to process customer.subscription.deleted: #{inspect(error)}")
    end
  end

  defp handle_event(%Stripe.Event{
         type: "customer.subscription.updated",
         data: %{object: stripe_sub}
       }) do
    Logger.info("Processing customer.subscription.updated for subscription #{stripe_sub.id}")

    with {:ok, subscription} <- get_subscription_by_stripe_id(stripe_sub.id),
         :ok <- validate_customer_ownership(subscription, stripe_sub.customer) do
      status = map_stripe_status(stripe_sub.status)
      {period_start, period_end} = get_period_from_subscription(stripe_sub)

      Billing.update_subscription!(
        subscription,
        %{
          status: status,
          current_period_start: period_start,
          current_period_end: period_end
        },
        authorize?: false
      )

      Logger.info("Synced subscription #{subscription.id} from Stripe")
    else
      {:error, :customer_mismatch} ->
        Logger.warning("Rejecting customer.subscription.updated event due to customer mismatch")

      error ->
        Logger.error("Failed to process customer.subscription.updated: #{inspect(error)}")
    end
  end

  defp handle_event(%Stripe.Event{type: type}) do
    Logger.debug("Ignoring unhandled Stripe event: #{type}")
  end

  defp get_organization_id(%{metadata: %{"organization_id" => org_id}}) when is_binary(org_id) do
    {:ok, org_id}
  end

  defp get_organization_id(%{subscription_data: %{metadata: %{"organization_id" => org_id}}})
       when is_binary(org_id) do
    {:ok, org_id}
  end

  defp get_organization_id(session) do
    Logger.error("No organization_id in session metadata: #{inspect(session.metadata)}")
    {:error, :missing_organization_id}
  end

  defp get_billing_period(%{subscription_data: %{metadata: %{"billing_period" => "annual"}}}),
    do: :annual

  defp get_billing_period(_), do: :monthly

  defp get_subscription_by_org(org_id) do
    case Billing.get_subscription_by_organization(org_id, authorize?: false) do
      {:ok, subscription} -> {:ok, subscription}
      _ -> {:error, :subscription_not_found}
    end
  end

  defp get_subscription_by_stripe_id(stripe_subscription_id) do
    require Ash.Query

    Citadel.Billing.Subscription
    |> Ash.Query.filter(stripe_subscription_id == ^stripe_subscription_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :subscription_not_found}
      {:ok, subscription} -> {:ok, subscription}
      error -> error
    end
  end

  defp get_subscription_by_stripe_sub_id(nil), do: {:error, :no_subscription_id}
  defp get_subscription_by_stripe_sub_id(id), do: get_subscription_by_stripe_id(id)

  defp get_stripe_subscription(nil), do: {:error, :no_subscription_id}

  defp get_stripe_subscription(subscription_id) do
    case Stripe.Subscription.retrieve(subscription_id) do
      {:ok, subscription} -> {:ok, subscription}
      error -> error
    end
  end

  defp unix_to_datetime(nil), do: nil

  defp unix_to_datetime(timestamp) when is_integer(timestamp) do
    DateTime.from_unix!(timestamp)
  end

  defp map_stripe_status("active"), do: :active
  defp map_stripe_status("past_due"), do: :past_due
  defp map_stripe_status("canceled"), do: :canceled
  defp map_stripe_status("trialing"), do: :trialing
  defp map_stripe_status(_), do: :active

  defp get_period_from_subscription(stripe_sub) do
    case stripe_sub.items do
      %{data: [first_item | _]} ->
        {
          unix_to_datetime(first_item.current_period_start),
          unix_to_datetime(first_item.current_period_end)
        }

      _ ->
        {nil, nil}
    end
  end

  defp get_subscription_id_from_invoice(invoice) do
    cond do
      is_binary(invoice.subscription) ->
        {:ok, invoice.subscription}

      match?(%{data: [%{subscription: sub_id} | _]} when is_binary(sub_id), invoice.lines) ->
        %{data: [%{subscription: sub_id} | _]} = invoice.lines
        {:ok, sub_id}

      true ->
        {:error, :no_subscription_id}
    end
  end

  defp validate_customer_ownership(subscription, webhook_customer_id) do
    cond do
      is_nil(subscription.stripe_customer_id) ->
        :ok

      is_nil(webhook_customer_id) ->
        :ok

      subscription.stripe_customer_id == webhook_customer_id ->
        :ok

      true ->
        Logger.error(
          "Customer ID mismatch - potential attack. " <>
            "Expected: #{subscription.stripe_customer_id}, " <>
            "Received: #{webhook_customer_id}, " <>
            "Subscription: #{subscription.id}"
        )

        {:error, :customer_mismatch}
    end
  end
end
