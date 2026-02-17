defmodule Citadel.Billing.StripeTest do
  use Citadel.DataCase, async: true

  alias Citadel.Billing.Plan

  setup do
    owner = generate(user())
    organization = generate(organization([], actor: owner))

    # Subscription is auto-created by the CreateStripeCustomer change
    # Fetch it from the organization
    require Ash.Query

    subscription =
      Citadel.Billing.Subscription
      |> Ash.Query.filter(organization_id == ^organization.id)
      |> Ash.read_one!(authorize?: false)

    {:ok, owner: owner, organization: organization, subscription: subscription}
  end

  describe "Plan integration" do
    test "stripe_price_id returns configured price ID" do
      # Uses test defaults from config/test.exs
      assert Plan.stripe_price_id(:pro, :monthly) == "price_test_pro_monthly"
    end

    test "stripe_seat_price_id returns configured seat price ID" do
      # Uses test defaults from config/test.exs
      assert Plan.stripe_seat_price_id(:pro, :annual) == "price_test_seat_annual"
    end

    test "free tier has nil price IDs" do
      assert Plan.stripe_price_id(:free, :monthly) == nil
      assert Plan.stripe_seat_price_id(:free, :monthly) == nil
    end
  end
end
