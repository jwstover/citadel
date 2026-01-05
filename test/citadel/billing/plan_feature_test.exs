defmodule Citadel.Billing.PlanFeatureTest do
  use Citadel.DataCase, async: true

  import Citadel.Generator

  alias Citadel.Billing.Plan

  describe "features/1" do
    test "returns MapSet of features for free tier" do
      features = Plan.features(:free)

      assert MapSet.member?(features, :basic_ai)
      refute MapSet.member?(features, :data_export)
      refute MapSet.member?(features, :api_access)
    end

    test "returns MapSet of features for pro tier" do
      features = Plan.features(:pro)

      assert MapSet.member?(features, :basic_ai)
      assert MapSet.member?(features, :advanced_ai_models)
      assert MapSet.member?(features, :data_export)
      assert MapSet.member?(features, :api_access)
      assert MapSet.member?(features, :byok)
      assert MapSet.member?(features, :team_collaboration)
      assert MapSet.member?(features, :multiple_workspaces)
    end
  end

  describe "tier_has_feature?/2" do
    test "free tier has basic_ai" do
      assert Plan.tier_has_feature?(:free, :basic_ai)
    end

    test "free tier does not have advanced features" do
      refute Plan.tier_has_feature?(:free, :data_export)
      refute Plan.tier_has_feature?(:free, :api_access)
      refute Plan.tier_has_feature?(:free, :byok)
      refute Plan.tier_has_feature?(:free, :advanced_ai_models)
      refute Plan.tier_has_feature?(:free, :team_collaboration)
      refute Plan.tier_has_feature?(:free, :multiple_workspaces)
      refute Plan.tier_has_feature?(:free, :bulk_import)
      refute Plan.tier_has_feature?(:free, :webhooks)
      refute Plan.tier_has_feature?(:free, :custom_branding)
      refute Plan.tier_has_feature?(:free, :priority_support)
    end

    test "pro tier has all features" do
      assert Plan.tier_has_feature?(:pro, :basic_ai)
      assert Plan.tier_has_feature?(:pro, :advanced_ai_models)
      assert Plan.tier_has_feature?(:pro, :data_export)
      assert Plan.tier_has_feature?(:pro, :api_access)
      assert Plan.tier_has_feature?(:pro, :byok)
      assert Plan.tier_has_feature?(:pro, :team_collaboration)
      assert Plan.tier_has_feature?(:pro, :multiple_workspaces)
      assert Plan.tier_has_feature?(:pro, :bulk_import)
      assert Plan.tier_has_feature?(:pro, :webhooks)
      assert Plan.tier_has_feature?(:pro, :custom_branding)
      assert Plan.tier_has_feature?(:pro, :priority_support)
    end
  end

  describe "org_has_feature?/2" do
    test "returns true when organization has feature (Pro tier)" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      generate(
        subscription(
          [organization_id: org.id, tier: :pro, billing_period: :monthly],
          authorize?: false
        )
      )

      assert {:ok, true} = Plan.org_has_feature?(org.id, :data_export)
      assert {:ok, true} = Plan.org_has_feature?(org.id, :api_access)
      assert {:ok, true} = Plan.org_has_feature?(org.id, :advanced_ai_models)
    end

    test "returns false when organization doesn't have feature (Free tier)" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Free tier subscription is created by default

      assert {:ok, false} = Plan.org_has_feature?(org.id, :data_export)
      assert {:ok, false} = Plan.org_has_feature?(org.id, :api_access)
      assert {:ok, false} = Plan.org_has_feature?(org.id, :advanced_ai_models)
    end

    test "returns true for basic_ai on free tier" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Free tier subscription is created by default

      assert {:ok, true} = Plan.org_has_feature?(org.id, :basic_ai)
    end

    test "returns error when organization doesn't exist" do
      fake_org_id = Ash.UUID.generate()

      assert {:error, _} = Plan.org_has_feature?(fake_org_id, :data_export)
    end
  end

  describe "features_for_tier/1" do
    test "returns list of features for free tier" do
      features = Plan.features_for_tier(:free)

      assert is_list(features)
      assert :basic_ai in features
      refute :data_export in features
    end

    test "returns list of features for pro tier" do
      features = Plan.features_for_tier(:pro)

      assert is_list(features)
      assert :basic_ai in features
      assert :data_export in features
      assert :api_access in features
      assert :advanced_ai_models in features
      assert :byok in features
      assert :team_collaboration in features
      assert :multiple_workspaces in features
      assert :bulk_import in features
      assert :webhooks in features
      assert :custom_branding in features
      assert :priority_support in features
    end
  end

  describe "all_tier_features/0" do
    test "returns map of tier to features" do
      all_features = Plan.all_tier_features()

      assert is_map(all_features)
      assert Map.has_key?(all_features, :free)
      assert Map.has_key?(all_features, :pro)

      assert is_list(all_features.free)
      assert is_list(all_features.pro)

      assert :basic_ai in all_features.free
      assert :data_export in all_features.pro
    end

    test "pro tier has more features than free tier" do
      all_features = Plan.all_tier_features()

      assert length(all_features.pro) > length(all_features.free)
    end
  end

  describe "allows_byok?/1 delegation to feature system" do
    test "delegates to tier_has_feature? for byok" do
      assert Plan.allows_byok?(:pro)
      refute Plan.allows_byok?(:free)
    end

    test "matches the byok feature availability" do
      assert Plan.allows_byok?(:pro) == Plan.tier_has_feature?(:pro, :byok)
      assert Plan.allows_byok?(:free) == Plan.tier_has_feature?(:free, :byok)
    end
  end
end
