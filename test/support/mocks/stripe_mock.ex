defmodule Citadel.Test.StripeMock do
  @moduledoc """
  Mock module for Stripe API calls in tests.

  This module provides mock responses for Stripe API calls. In tests,
  you can configure the mock behavior using the process dictionary:

      # Successful customer creation
      Process.put(:stripe_customer_response, {:ok, %{id: "cus_test_123"}})

      # Failed customer creation
      Process.put(:stripe_customer_response, {:error, %Stripe.Error{message: "Failed"}})

  If no mock response is configured, defaults are returned.
  """

  @doc """
  Mock implementation of Stripe.Customer.create/1.
  """
  def create_customer(_params) do
    case Process.get(:stripe_customer_response) do
      nil -> {:ok, %Stripe.Customer{id: "cus_test_#{unique_id()}"}}
      response -> response
    end
  end

  @doc """
  Mock implementation of Stripe.Checkout.Session.create/1.
  """
  def create_checkout_session(_params) do
    case Process.get(:stripe_checkout_response) do
      nil ->
        {:ok,
         %Stripe.Checkout.Session{
           id: "cs_test_#{unique_id()}",
           url: "https://checkout.stripe.com/test_session"
         }}

      response ->
        response
    end
  end

  @doc """
  Mock implementation of Stripe.Subscription.retrieve/1.
  """
  def retrieve_subscription(_id) do
    case Process.get(:stripe_subscription_response) do
      nil ->
        {:ok,
         %Stripe.Subscription{
           id: "sub_test_#{unique_id()}",
           status: "active",
           current_period_start: DateTime.utc_now() |> DateTime.to_unix(),
           current_period_end: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_unix(),
           items: %Stripe.List{data: []}
         }}

      response ->
        response
    end
  end

  @doc """
  Mock implementation of Stripe.Subscription.update/2.
  """
  def update_subscription(id, _params) do
    case Process.get(:stripe_subscription_update_response) do
      nil ->
        {:ok,
         %Stripe.Subscription{
           id: id,
           status: "active",
           current_period_start: DateTime.utc_now() |> DateTime.to_unix(),
           current_period_end: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_unix()
         }}

      response ->
        response
    end
  end

  @doc """
  Mock implementation of Stripe.BillingPortal.Session.create/1.
  """
  def create_portal_session(_params) do
    case Process.get(:stripe_portal_response) do
      nil -> {:ok, %{url: "https://billing.stripe.com/test_portal"}}
      response -> response
    end
  end

  @doc """
  Mock implementation of Stripe.Webhook.construct_event/3.
  """
  def construct_event(payload, _signature, _secret) do
    case Process.get(:stripe_webhook_response) do
      nil ->
        # Try to parse the payload and construct an event
        case Jason.decode(payload) do
          {:ok, data} ->
            {:ok,
             %Stripe.Event{
               id: "evt_test_#{unique_id()}",
               type: data["type"],
               data: %{object: data["data"]["object"]}
             }}

          _ ->
            {:error, "Invalid payload"}
        end

      response ->
        response
    end
  end

  defp unique_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
