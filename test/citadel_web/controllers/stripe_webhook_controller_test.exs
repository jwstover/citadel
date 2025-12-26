defmodule CitadelWeb.StripeWebhookControllerTest do
  use CitadelWeb.ConnCase, async: true

  import Ecto.Query

  alias Citadel.Billing
  alias Citadel.Billing.ProcessedWebhookEvent

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

  describe "webhook replay attack protection" do
    test "recording a new event marks it as processed" do
      event_id = "evt_test_#{System.unique_integer([:positive])}"
      event_type = "checkout.session.completed"

      assert {:ok, false} = Billing.event_processed?(event_id, authorize?: false)

      Billing.record_webhook_event!(event_id, event_type, authorize?: false)

      assert {:ok, true} = Billing.event_processed?(event_id, authorize?: false)
    end

    test "duplicate event IDs are detected" do
      event_id = "evt_test_#{System.unique_integer([:positive])}"
      event_type = "invoice.paid"

      Billing.record_webhook_event!(event_id, event_type, authorize?: false)

      assert {:ok, true} = Billing.event_processed?(event_id, authorize?: false)
    end

    test "different event IDs are not marked as duplicates" do
      event_id_1 = "evt_test_#{System.unique_integer([:positive])}"
      event_id_2 = "evt_test_#{System.unique_integer([:positive])}"

      Billing.record_webhook_event!(event_id_1, "test.event", authorize?: false)

      assert {:ok, true} = Billing.event_processed?(event_id_1, authorize?: false)
      assert {:ok, false} = Billing.event_processed?(event_id_2, authorize?: false)
    end

    test "cleanup removes old events" do
      require Ash.Query

      old_event_id = "evt_old_#{System.unique_integer([:positive])}"

      # Create an old event
      {:ok, old_event} =
        ProcessedWebhookEvent
        |> Ash.Changeset.for_create(:record, %{
          stripe_event_id: old_event_id,
          event_type: "test.event"
        })
        |> Ash.create(authorize?: false)

      # Manually set processed_at to 31 days ago
      old_timestamp = DateTime.utc_now() |> DateTime.add(-31, :day)

      # Convert UUID string to binary for Postgres
      {:ok, uuid_binary} = Ecto.UUID.dump(old_event.id)

      Citadel.Repo.update_all(
        from(e in "processed_webhook_events", where: e.id == ^uuid_binary),
        set: [processed_at: old_timestamp]
      )

      # Create a recent event
      recent_event_id = "evt_recent_#{System.unique_integer([:positive])}"
      Billing.record_webhook_event!(recent_event_id, "test.event", authorize?: false)

      # Run cleanup
      {:ok, count} = Billing.cleanup_old_webhook_events(%{older_than_days: 30}, authorize?: false)
      assert count == 1

      # Old event should be gone
      assert {:ok, false} = Billing.event_processed?(old_event_id, authorize?: false)

      # Recent event should still exist
      assert {:ok, true} = Billing.event_processed?(recent_event_id, authorize?: false)
    end

    test "recording same event ID twice raises error" do
      event_id = "evt_test_#{System.unique_integer([:positive])}"

      Billing.record_webhook_event!(event_id, "test.event", authorize?: false)

      assert_raise Ash.Error.Invalid, fn ->
        Billing.record_webhook_event!(event_id, "test.event", authorize?: false)
      end
    end
  end
end
