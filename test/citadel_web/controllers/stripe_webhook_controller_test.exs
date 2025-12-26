defmodule CitadelWeb.StripeWebhookControllerTest do
  use CitadelWeb.ConnCase, async: true

  alias Citadel.Billing

  setup do
    owner = generate(user())
    organization = generate(organization([], actor: owner))

    # Subscription is auto-created by the CreateStripeCustomer change
    require Ash.Query

    subscription =
      Citadel.Billing.Subscription
      |> Ash.Query.filter(organization_id == ^organization.id)
      |> Ash.read_one!(authorize?: false)

    # Set stripe_customer_id for tests that need it
    subscription =
      Billing.update_subscription!(
        subscription,
        %{stripe_customer_id: "cus_test_123"},
        authorize?: false
      )

    {:ok, owner: owner, organization: organization, subscription: subscription}
  end

  describe "handle/2" do
    test "returns 400 when signature is missing", %{conn: conn} do
      # Manually set raw_body since we're bypassing the body reader plug
      body = ~s({"type": "test.event"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign(:raw_body, body)
        |> post("/webhooks/stripe", %{type: "test.event"})

      assert response(conn, 400) =~ "Missing Stripe signature"
    end

    test "returns 400 when raw body is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", "test_sig")
        |> post("/webhooks/stripe", %{type: "test.event"})

      # raw_body is nil since we didn't assign it
      assert response(conn, 400) =~ "Missing request body"
    end

    test "returns 400 when signature verification fails", %{conn: conn} do
      body = ~s({"type": "test.event"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", "invalid_signature")
        |> assign(:raw_body, body)
        |> post("/webhooks/stripe", %{type: "test.event"})

      assert response(conn, 400) =~ "Webhook verification failed"
    end
  end

  describe "webhook event processing (unit tests)" do
    test "subscription update action works correctly", %{subscription: subscription} do
      # Test that we can update subscriptions as the webhook handler would
      updated =
        Billing.update_subscription!(
          subscription,
          %{
            tier: :pro,
            status: :active,
            billing_period: :monthly,
            stripe_subscription_id: "sub_test_456",
            current_period_start: DateTime.utc_now() |> DateTime.truncate(:second),
            current_period_end:
              DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
          },
          authorize?: false
        )

      assert updated.tier == :pro
      assert updated.status == :active
      assert updated.billing_period == :monthly
      assert updated.stripe_subscription_id == "sub_test_456"
      assert updated.current_period_start != nil
      assert updated.current_period_end != nil
    end

    test "subscription can be marked as past_due", %{subscription: subscription} do
      updated =
        Billing.update_subscription!(
          subscription,
          %{status: :past_due},
          authorize?: false
        )

      assert updated.status == :past_due
    end

    test "subscription can be cancelled", %{subscription: subscription} do
      updated =
        Billing.update_subscription!(
          subscription,
          %{status: :canceled},
          authorize?: false
        )

      assert updated.status == :canceled
    end

    test "subscription can be found by stripe_subscription_id", %{
      subscription: subscription,
      organization: organization
    } do
      require Ash.Query

      # Set a unique stripe_subscription_id
      stripe_sub_id = "sub_unique_#{System.unique_integer([:positive])}"

      Billing.update_subscription!(
        subscription,
        %{stripe_subscription_id: stripe_sub_id},
        authorize?: false
      )

      # Find by stripe_subscription_id (as webhook handler would)
      found =
        Citadel.Billing.Subscription
        |> Ash.Query.filter(stripe_subscription_id == ^stripe_sub_id)
        |> Ash.read_one!(authorize?: false)

      assert found.id == subscription.id
      assert found.organization_id == organization.id
    end
  end
end
