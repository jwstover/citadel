defmodule Citadel.Billing.PlanTest do
  use ExUnit.Case, async: true

  alias Citadel.Billing.Plan

  describe "get/1" do
    test "returns free plan configuration" do
      plan = Plan.get(:free)

      assert plan.name == "Free"
      assert plan.monthly_credits == 500
      assert plan.max_workspaces == 1
      assert plan.max_members_per_workspace == 1
      assert plan.monthly_price_cents == 0
      assert plan.annual_price_cents == 0
    end

    test "returns pro plan configuration" do
      plan = Plan.get(:pro)

      assert plan.name == "Pro"
      assert plan.monthly_credits == 10_000
      assert plan.max_workspaces == 5
      assert plan.max_members_per_workspace == :unlimited
      assert plan.monthly_price_cents == 1900
      assert plan.annual_price_cents == 19_000
      assert plan.per_member_monthly_cents == 500
      assert plan.per_member_annual_cents == 5000
    end
  end

  describe "monthly_credits/1" do
    test "returns 500 for free tier" do
      assert Plan.monthly_credits(:free) == 500
    end

    test "returns 10_000 for pro tier" do
      assert Plan.monthly_credits(:pro) == 10_000
    end
  end

  describe "max_workspaces/1" do
    test "returns 1 for free tier" do
      assert Plan.max_workspaces(:free) == 1
    end

    test "returns 5 for pro tier" do
      assert Plan.max_workspaces(:pro) == 5
    end
  end

  describe "max_members_per_workspace/1" do
    test "returns 1 for free tier" do
      assert Plan.max_members_per_workspace(:free) == 1
    end

    test "returns :unlimited for pro tier" do
      assert Plan.max_members_per_workspace(:pro) == :unlimited
    end
  end

  describe "base_price_cents/2" do
    test "returns 0 for free tier monthly" do
      assert Plan.base_price_cents(:free, :monthly) == 0
    end

    test "returns 0 for free tier annual" do
      assert Plan.base_price_cents(:free, :annual) == 0
    end

    test "returns 1900 for pro tier monthly" do
      assert Plan.base_price_cents(:pro, :monthly) == 1900
    end

    test "returns 19000 for pro tier annual" do
      assert Plan.base_price_cents(:pro, :annual) == 19_000
    end
  end

  describe "per_member_price_cents/2" do
    test "returns 0 for free tier" do
      assert Plan.per_member_price_cents(:free, :monthly) == 0
      assert Plan.per_member_price_cents(:free, :annual) == 0
    end

    test "returns 500 for pro tier monthly" do
      assert Plan.per_member_price_cents(:pro, :monthly) == 500
    end

    test "returns 5000 for pro tier annual" do
      assert Plan.per_member_price_cents(:pro, :annual) == 5000
    end
  end

  describe "allows_workspace_count?/2" do
    test "free tier allows 1 workspace" do
      assert Plan.allows_workspace_count?(:free, 1) == true
      assert Plan.allows_workspace_count?(:free, 2) == false
    end

    test "pro tier allows up to 5 workspaces" do
      assert Plan.allows_workspace_count?(:pro, 1) == true
      assert Plan.allows_workspace_count?(:pro, 5) == true
      assert Plan.allows_workspace_count?(:pro, 6) == false
    end
  end

  describe "allows_member_count?/2" do
    test "free tier allows only 1 member" do
      assert Plan.allows_member_count?(:free, 1) == true
      assert Plan.allows_member_count?(:free, 2) == false
    end

    test "pro tier allows unlimited members" do
      assert Plan.allows_member_count?(:pro, 1) == true
      assert Plan.allows_member_count?(:pro, 100) == true
      assert Plan.allows_member_count?(:pro, 1000) == true
    end
  end

  describe "list_tiers/0" do
    test "returns all available tiers" do
      assert Plan.list_tiers() == [:free, :pro]
    end
  end

  describe "stripe_price_id/2" do
    test "returns nil by default (not configured)" do
      assert Plan.stripe_price_id(:free, :monthly) == nil
      assert Plan.stripe_price_id(:free, :annual) == nil
      assert Plan.stripe_price_id(:pro, :monthly) == nil
      assert Plan.stripe_price_id(:pro, :annual) == nil
    end
  end

  describe "stripe_seat_price_id/2" do
    test "returns nil by default (not configured)" do
      assert Plan.stripe_seat_price_id(:free, :monthly) == nil
      assert Plan.stripe_seat_price_id(:free, :annual) == nil
      assert Plan.stripe_seat_price_id(:pro, :monthly) == nil
      assert Plan.stripe_seat_price_id(:pro, :annual) == nil
    end
  end
end
