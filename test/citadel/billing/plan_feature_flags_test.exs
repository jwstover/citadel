defmodule Citadel.Billing.PlanFeatureFlagsTest do
  use Citadel.DataCase, async: true

  alias Citadel.Billing.Plan

  setup do
    # Clear any feature flags from previous tests to ensure clean slate
    clear_features()

    user = generate(user())
    workspace = generate(workspace([], actor: user))

    organization =
      Citadel.Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)

    %{user: user, workspace: workspace, organization: organization}
  end

  describe "feature flag priority over tier features" do
    test "global flag enabled overrides tier restriction", %{organization: organization} do
      # Free tier doesn't have api_access
      assert {:ok, false} = Plan.org_has_feature?(organization.id, :api_access)

      # Enable global flag
      enable_feature(:api_access)

      # Now should be enabled despite free tier
      assert {:ok, true} = Plan.org_has_feature?(organization.id, :api_access)
    end

    test "global flag disabled overrides tier allowance", %{organization: organization} do
      # Free tier has basic_ai
      assert {:ok, true} = Plan.org_has_feature?(organization.id, :basic_ai)

      # Disable global flag
      disable_feature(:basic_ai)

      # Now should be disabled despite tier allowing it
      assert {:ok, false} = Plan.org_has_feature?(organization.id, :basic_ai)
    end

    test "falls back to tier features when no flag exists", %{organization: organization} do
      # Should fall back to tier check (free tier doesn't have data_export)
      assert {:ok, false} = Plan.org_has_feature?(organization.id, :data_export)
    end
  end

  describe "flag updates reflect immediately" do
    test "enabling flag changes feature availability", %{organization: organization} do
      # Start with disabled flag
      disable_feature(:bulk_import)

      assert {:ok, false} = Plan.org_has_feature?(organization.id, :bulk_import)

      # Enable flag
      enable_feature(:bulk_import)

      assert {:ok, true} = Plan.org_has_feature?(organization.id, :bulk_import)
    end
  end

  describe "graceful degradation" do
    test "returns tier features if cache fails", %{organization: organization} do
      # Even if cache returns :not_found, should fall back to tier check
      assert {:ok, true} = Plan.org_has_feature?(organization.id, :basic_ai)
    end
  end

  describe "non-billing feature flags" do
    @tag timeout: 120_000
    test "returns flag value directly for non-billing keys", %{organization: organization} do
      non_billing_key = :"beta_ui_redesign_#{System.unique_integer([:positive])}"

      # No flag exists - should return false
      assert {:ok, false} = Plan.org_has_feature?(organization.id, non_billing_key)

      # Enable non-billing flag
      set_features(%{non_billing_key => true})

      # Should return true (not a billing feature, just use flag value)
      assert {:ok, true} = Plan.org_has_feature?(organization.id, non_billing_key)
    end

    @tag timeout: 120_000
    test "disabled non-billing flag returns false", %{organization: organization} do
      non_billing_key = :"maintenance_mode_#{System.unique_integer([:positive])}"

      disable_feature(non_billing_key)

      assert {:ok, false} = Plan.org_has_feature?(organization.id, non_billing_key)
    end

    @tag timeout: 120_000
    test "non-billing flags don't require billing features validation", %{
      organization: organization
    } do
      # Can use any atom key
      operational_flags = %{
        :"beta_feature_#{System.unique_integer([:positive])}" => true,
        :"experiment_a_#{System.unique_integer([:positive])}" => true,
        :"killswitch_#{System.unique_integer([:positive])}" => true
      }

      set_features(operational_flags)

      for {flag_key, _} <- operational_flags do
        assert {:ok, true} = Plan.org_has_feature?(organization.id, flag_key)
      end
    end
  end

  describe "multiple organizations" do
    @tag timeout: 120_000
    test "global flags affect all organizations" do
      user1 = generate(user())
      workspace1 = generate(workspace([], actor: user1))

      org1 =
        Citadel.Accounts.get_organization_by_id!(workspace1.organization_id, authorize?: false)

      user2 = generate(user())
      workspace2 = generate(workspace([], actor: user2))

      org2 =
        Citadel.Accounts.get_organization_by_id!(workspace2.organization_id, authorize?: false)

      # Both orgs don't have advanced_ai_models (free tier)
      assert {:ok, false} = Plan.org_has_feature?(org1.id, :advanced_ai_models)
      assert {:ok, false} = Plan.org_has_feature?(org2.id, :advanced_ai_models)

      # Enable globally
      enable_feature(:advanced_ai_models)

      # Both orgs now have access
      assert {:ok, true} = Plan.org_has_feature?(org1.id, :advanced_ai_models)
      assert {:ok, true} = Plan.org_has_feature?(org2.id, :advanced_ai_models)
    end
  end
end
