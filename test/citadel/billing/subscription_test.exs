defmodule Citadel.Billing.SubscriptionTest do
  use Citadel.DataCase, async: true

  alias Citadel.Billing

  setup do
    owner = generate(user())
    organization = generate(organization([], actor: owner))

    {:ok, owner: owner, organization: organization}
  end

  describe "create_subscription/2" do
    test "creates a free subscription with defaults", %{organization: organization} do
      assert subscription =
               Billing.create_subscription!(organization.id, :free, authorize?: false)

      assert subscription.organization_id == organization.id
      assert subscription.tier == :free
      assert subscription.status == :active
      assert subscription.billing_period == nil
      assert subscription.seat_count == 1
      assert subscription.stripe_subscription_id == nil
      assert subscription.stripe_customer_id == nil
    end

    test "creates a pro subscription with billing period", %{organization: organization} do
      assert subscription =
               Billing.create_subscription!(
                 organization.id,
                 :pro,
                 %{billing_period: :monthly},
                 authorize?: false
               )

      assert subscription.tier == :pro
      assert subscription.billing_period == :monthly
      assert subscription.status == :active
    end

    test "creates a pro subscription with annual billing", %{organization: organization} do
      assert subscription =
               Billing.create_subscription!(
                 organization.id,
                 :pro,
                 %{billing_period: :annual},
                 authorize?: false
               )

      assert subscription.tier == :pro
      assert subscription.billing_period == :annual
    end

    test "fails to create pro subscription without billing period", %{organization: organization} do
      assert_raise Ash.Error.Invalid, fn ->
        Billing.create_subscription!(organization.id, :pro, authorize?: false)
      end
    end

    test "enforces unique organization constraint", %{organization: organization} do
      Billing.create_subscription!(organization.id, :free, authorize?: false)

      assert_raise Ash.Error.Invalid, fn ->
        Billing.create_subscription!(organization.id, :free, authorize?: false)
      end
    end
  end

  describe "get_subscription_by_organization/2" do
    test "retrieves subscription by organization id", %{
      owner: owner,
      organization: organization
    } do
      subscription = Billing.create_subscription!(organization.id, :free, authorize?: false)

      assert found = Billing.get_subscription_by_organization!(organization.id, actor: owner)
      assert found.id == subscription.id
      assert found.organization_id == organization.id
    end

    test "returns error when organization has no subscription", %{owner: owner} do
      other_org = generate(organization([], actor: owner))

      assert {:error, %Ash.Error.Invalid{}} =
               Billing.get_subscription_by_organization(other_org.id, actor: owner)
    end
  end

  describe "upgrade_to_pro/2" do
    test "upgrades free subscription to pro", %{owner: owner, organization: organization} do
      subscription = Billing.create_subscription!(organization.id, :free, authorize?: false)

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

    test "can set stripe ids during upgrade", %{owner: owner, organization: organization} do
      subscription = Billing.create_subscription!(organization.id, :free, authorize?: false)

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
  end

  describe "cancel_subscription/2" do
    test "cancels an active subscription", %{owner: owner, organization: organization} do
      subscription =
        Billing.create_subscription!(
          organization.id,
          :pro,
          %{billing_period: :monthly},
          authorize?: false
        )

      assert subscription.status == :active

      canceled = Billing.cancel_subscription!(subscription, actor: owner)

      assert canceled.status == :canceled
      assert canceled.tier == :pro
    end
  end

  describe "update_subscription/2" do
    test "updates stripe fields", %{owner: owner, organization: organization} do
      subscription = Billing.create_subscription!(organization.id, :free, authorize?: false)

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
  end

  describe "authorization" do
    test "organization owner can read subscription", %{owner: owner, organization: organization} do
      Billing.create_subscription!(organization.id, :free, authorize?: false)

      assert {:ok, subscription} =
               Billing.get_subscription_by_organization(organization.id, actor: owner)

      assert subscription.organization_id == organization.id
    end

    test "organization member can read subscription", %{organization: organization} do
      Billing.create_subscription!(organization.id, :free, authorize?: false)

      member = generate(user())

      generate(
        organization_membership(
          [organization_id: organization.id, user_id: member.id, role: :member],
          authorize?: false
        )
      )

      assert {:ok, subscription} =
               Billing.get_subscription_by_organization(organization.id, actor: member)

      assert subscription.organization_id == organization.id
    end

    test "non-member cannot read subscription", %{organization: organization} do
      Billing.create_subscription!(organization.id, :free, authorize?: false)

      non_member = generate(user())

      assert {:error, %Ash.Error.Invalid{}} =
               Billing.get_subscription_by_organization(organization.id, actor: non_member)
    end

    test "organization admin can update subscription", %{organization: organization} do
      subscription = Billing.create_subscription!(organization.id, :free, authorize?: false)

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

    test "regular member cannot update subscription", %{organization: organization} do
      subscription = Billing.create_subscription!(organization.id, :free, authorize?: false)

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
