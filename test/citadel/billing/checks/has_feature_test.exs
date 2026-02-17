defmodule Citadel.Billing.Checks.HasFeatureTest do
  use Citadel.DataCase, async: true

  import Citadel.Generator

  alias Citadel.Billing.Checks.HasFeature

  describe "HasFeature check with Pro organization" do
    test "returns true when organization has the feature" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      generate(
        subscription(
          [organization_id: org.id, tier: :pro, billing_period: :monthly],
          authorize?: false
        )
      )

      context = build_context_with_org(org.id)

      assert HasFeature.match?(owner, context, feature: :data_export)
      assert HasFeature.match?(owner, context, feature: :api_access)
      assert HasFeature.match?(owner, context, feature: :advanced_ai_models)
    end

    test "returns true for basic_ai feature" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      generate(
        subscription(
          [organization_id: org.id, tier: :pro, billing_period: :monthly],
          authorize?: false
        )
      )

      context = build_context_with_org(org.id)

      assert HasFeature.match?(owner, context, feature: :basic_ai)
    end
  end

  describe "HasFeature check with Free organization" do
    test "returns false when organization doesn't have the feature" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Free tier subscription created by default

      context = build_context_with_org(org.id)

      refute HasFeature.match?(owner, context, feature: :data_export)
      refute HasFeature.match?(owner, context, feature: :api_access)
      refute HasFeature.match?(owner, context, feature: :advanced_ai_models)
    end

    test "returns true for basic_ai feature on free tier" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Free tier subscription created by default

      context = build_context_with_org(org.id)

      assert HasFeature.match?(owner, context, feature: :basic_ai)
    end
  end

  describe "HasFeature check with feature flag overrides" do
    test "respects enabled flag override - grants access to free tier" do
      enable_feature(:api_access)

      owner = generate(user())
      org = generate(organization([], actor: owner))

      context = build_context_with_org(org.id)

      assert HasFeature.match?(owner, context, feature: :api_access)
    end

    test "respects disabled flag override - denies access to pro tier" do
      disable_feature(:api_access)

      owner = generate(user())
      org = generate(organization([], actor: owner))

      generate(
        subscription(
          [organization_id: org.id, tier: :pro, billing_period: :monthly],
          authorize?: false
        )
      )

      context = build_context_with_org(org.id)

      refute HasFeature.match?(owner, context, feature: :api_access)
    end

    test "falls back to tier when no flag exists" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      generate(
        subscription(
          [organization_id: org.id, tier: :pro, billing_period: :monthly],
          authorize?: false
        )
      )

      context = build_context_with_org(org.id)

      assert HasFeature.match?(owner, context, feature: :data_export)
    end

    test "flag override for one feature doesn't affect others" do
      enable_feature(:api_access)

      owner = generate(user())
      org = generate(organization([], actor: owner))

      context = build_context_with_org(org.id)

      assert HasFeature.match?(owner, context, feature: :api_access)
      refute HasFeature.match?(owner, context, feature: :data_export)
    end
  end

  describe "HasFeature check error cases" do
    test "returns false when no organization is provided" do
      owner = generate(user())

      context = %{}

      refute HasFeature.match?(owner, context, feature: :data_export)
    end

    test "returns false for nil actor" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      context = build_context_with_org(org.id)

      refute HasFeature.match?(nil, context, feature: :data_export)
    end

    test "raises ArgumentError for invalid feature" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      context = build_context_with_org(org.id)

      assert_raise ArgumentError, ~r/Invalid feature/, fn ->
        HasFeature.match?(owner, context, feature: :invalid_feature_123)
      end
    end
  end

  describe "HasFeature check context extraction" do
    test "extracts organization_id from changeset attribute" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      generate(
        subscription(
          [organization_id: org.id, tier: :pro, billing_period: :monthly],
          authorize?: false
        )
      )

      changeset = %Ash.Changeset{
        action_type: :create,
        resource: Citadel.Tasks.Task,
        attributes: %{organization_id: org.id}
      }

      context = %{changeset: changeset}

      assert HasFeature.match?(owner, context, feature: :data_export)
    end

    test "extracts organization_id from context data" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      generate(
        subscription(
          [organization_id: org.id, tier: :pro, billing_period: :monthly],
          authorize?: false
        )
      )

      context = %{data: %{organization_id: org.id}}

      assert HasFeature.match?(owner, context, feature: :data_export)
    end

    test "returns false when organization_id is nil in context" do
      owner = generate(user())

      context = %{data: %{organization_id: nil}}

      refute HasFeature.match?(owner, context, feature: :data_export)
    end
  end

  describe "HasFeature describe/1" do
    test "returns feature name in description" do
      description = HasFeature.describe(feature: :data_export)
      assert description =~ "Data Export"
    end

    test "returns description for different features" do
      description = HasFeature.describe(feature: :api_access)
      assert description =~ "API Access"

      description = HasFeature.describe(feature: :advanced_ai_models)
      assert description =~ "Advanced AI Models"
    end
  end

  # Helper Functions

  defp build_context_with_org(organization_id) do
    changeset = %Ash.Changeset{
      action_type: :create,
      resource: Citadel.Tasks.Task,
      attributes: %{organization_id: organization_id}
    }

    %{changeset: changeset}
  end
end
