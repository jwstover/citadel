defmodule Citadel.Billing.SubscriptionTest do
  use Citadel.DataCase, async: true

  alias Citadel.Billing

  setup do
    owner = generate(user())
    organization = generate(organization([], actor: owner))

    # Get the auto-created subscription
    subscription = Billing.get_subscription_by_organization!(organization.id, authorize?: false)

    {:ok, owner: owner, organization: organization, subscription: subscription}
  end

  describe "auto-created subscription" do
    test "organization has a free subscription created automatically", %{
      subscription: subscription,
      organization: organization
    } do
      assert subscription.organization_id == organization.id
      assert subscription.tier == :free
      assert subscription.status == :active
      assert subscription.seat_count == 1
      assert subscription.current_period_start != nil
      assert subscription.current_period_end != nil
    end

    test "enforces unique organization constraint", %{organization: organization} do
      # Trying to create another subscription for the same org should fail
      assert_raise Ash.Error.Invalid, fn ->
        Billing.create_subscription!(organization.id, :free, authorize?: false)
      end
    end
  end

  describe "get_subscription_by_organization/2" do
    test "retrieves subscription by organization id", %{
      owner: owner,
      organization: organization,
      subscription: subscription
    } do
      assert found = Billing.get_subscription_by_organization!(organization.id, actor: owner)
      assert found.id == subscription.id
      assert found.organization_id == organization.id
    end

    test "returns error for non-existent organization", %{owner: owner} do
      fake_id = Ash.UUID.generate()

      assert {:error, %Ash.Error.Invalid{}} =
               Billing.get_subscription_by_organization(fake_id, actor: owner)
    end
  end

  describe "upgrade_to_pro/2" do
    test "upgrades free subscription to pro", %{owner: owner, subscription: subscription} do
      assert subscription.tier == :free

      upgraded =
        Billing.upgrade_to_pro!(
          subscription,
          %{billing_period: :monthly},
          actor: owner
        )

      assert upgraded.tier == :pro
      assert upgraded.billing_period == :monthly
      assert upgraded.status == :active
    end

    test "can set stripe ids during upgrade", %{owner: owner, subscription: subscription} do
      upgraded =
        Billing.upgrade_to_pro!(
          subscription,
          %{
            billing_period: :monthly,
            stripe_subscription_id: "sub_123",
            stripe_customer_id: "cus_456"
          },
          actor: owner
        )

      assert upgraded.stripe_subscription_id == "sub_123"
      assert upgraded.stripe_customer_id == "cus_456"
    end

    test "upgrade to annual billing", %{owner: owner, subscription: subscription} do
      upgraded =
        Billing.upgrade_to_pro!(
          subscription,
          %{billing_period: :annual},
          actor: owner
        )

      assert upgraded.tier == :pro
      assert upgraded.billing_period == :annual
    end
  end

  describe "cancel_subscription/2" do
    test "cancels an active subscription", %{owner: owner, subscription: subscription} do
      # First upgrade to pro
      subscription =
        Billing.upgrade_to_pro!(
          subscription,
          %{billing_period: :monthly},
          actor: owner
        )

      assert subscription.status == :active

      canceled = Billing.cancel_subscription!(subscription, actor: owner)

      assert canceled.status == :canceled
      assert canceled.tier == :pro
    end
  end

  describe "update_subscription/2" do
    test "updates stripe fields", %{owner: owner, subscription: subscription} do
      updated =
        Billing.update_subscription!(
          subscription,
          %{
            stripe_customer_id: "cus_789",
            seat_count: 5
          },
          actor: owner
        )

      assert updated.stripe_customer_id == "cus_789"
      assert updated.seat_count == 5
    end

    test "updates tier and billing period", %{owner: owner, subscription: subscription} do
      updated =
        Billing.update_subscription!(
          subscription,
          %{
            tier: :pro,
            billing_period: :monthly
          },
          actor: owner
        )

      assert updated.tier == :pro
      assert updated.billing_period == :monthly
    end

    test "updates period dates", %{owner: owner, subscription: subscription} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      period_end = DateTime.add(now, 30, :day)

      updated =
        Billing.update_subscription!(
          subscription,
          %{
            current_period_start: now,
            current_period_end: period_end
          },
          actor: owner
        )

      assert updated.current_period_start == now
      assert updated.current_period_end == period_end
    end
  end

  describe "authorization" do
    test "organization owner can read subscription", %{
      owner: owner,
      organization: organization,
      subscription: subscription
    } do
      assert {:ok, found} =
               Billing.get_subscription_by_organization(organization.id, actor: owner)

      assert found.id == subscription.id
    end

    test "organization member can read subscription", %{
      organization: organization,
      subscription: subscription
    } do
      member = generate(user())

      generate(
        organization_membership(
          [organization_id: organization.id, user_id: member.id, role: :member],
          authorize?: false
        )
      )

      assert {:ok, found} =
               Billing.get_subscription_by_organization(organization.id, actor: member)

      assert found.id == subscription.id
    end

    test "non-member cannot read subscription", %{organization: organization} do
      non_member = generate(user())

      assert {:error, %Ash.Error.Invalid{}} =
               Billing.get_subscription_by_organization(organization.id, actor: non_member)
    end

    test "organization admin can update subscription", %{
      organization: organization,
      subscription: subscription
    } do
      admin = generate(user())

      generate(
        organization_membership(
          [organization_id: organization.id, user_id: admin.id, role: :admin],
          authorize?: false
        )
      )

      assert updated =
               Billing.update_subscription!(
                 subscription,
                 %{seat_count: 3},
                 actor: admin
               )

      assert updated.seat_count == 3
    end

    test "regular member cannot update subscription", %{
      organization: organization,
      subscription: subscription
    } do
      member = generate(user())

      generate(
        organization_membership(
          [organization_id: organization.id, user_id: member.id, role: :member],
          authorize?: false
        )
      )

      assert_raise Ash.Error.Forbidden, fn ->
        Billing.update_subscription!(subscription, %{seat_count: 3}, actor: member)
      end
    end
  end
end
