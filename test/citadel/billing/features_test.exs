defmodule Citadel.Billing.FeaturesTest do
  use ExUnit.Case, async: true

  alias Citadel.Billing.Features

  describe "get/1" do
    test "returns metadata for valid feature" do
      metadata = Features.get(:data_export)

      assert metadata.name == "Data Export"
      assert metadata.description == "Export your tasks and conversations in CSV/JSON format"
      assert metadata.category == :data
      assert metadata.type == :binary
    end

    test "returns metadata for AI features" do
      metadata = Features.get(:advanced_ai_models)

      assert metadata.name == "Advanced AI Models"
      assert metadata.category == :ai
    end

    test "returns nil for invalid feature" do
      assert Features.get(:invalid_feature_123) == nil
    end
  end

  describe "name/1" do
    test "returns display name for valid feature" do
      assert Features.name(:data_export) == "Data Export"
      assert Features.name(:api_access) == "API Access"
      assert Features.name(:byok) == "Bring Your Own Key"
    end

    test "returns stringified atom for invalid feature" do
      assert Features.name(:invalid_feature) == "invalid_feature"
    end
  end

  describe "description/1" do
    test "returns description for valid feature" do
      description = Features.description(:data_export)
      assert description == "Export your tasks and conversations in CSV/JSON format"
    end

    test "returns empty string for invalid feature" do
      assert Features.description(:invalid_feature) == ""
    end
  end

  describe "category/1" do
    test "returns category for valid feature" do
      assert Features.category(:data_export) == :data
      assert Features.category(:api_access) == :api
      assert Features.category(:advanced_ai_models) == :ai
      assert Features.category(:team_collaboration) == :collaboration
    end

    test "returns nil for invalid feature" do
      assert Features.category(:invalid_feature) == nil
    end
  end

  describe "list_all/0" do
    test "returns all feature atoms" do
      features = Features.list_all()

      assert is_list(features)
      assert :basic_ai in features
      assert :advanced_ai_models in features
      assert :data_export in features
      assert :api_access in features
      assert :byok in features
      assert :team_collaboration in features
      assert :multiple_workspaces in features
      assert :bulk_import in features
      assert :webhooks in features
      assert :custom_branding in features
      assert :priority_support in features
    end
  end

  describe "by_category/1" do
    test "returns all AI features" do
      ai_features = Features.by_category(:ai)

      assert :basic_ai in ai_features
      assert :advanced_ai_models in ai_features
      assert :byok in ai_features
    end

    test "returns all collaboration features" do
      collab_features = Features.by_category(:collaboration)

      assert :multiple_workspaces in collab_features
      assert :team_collaboration in collab_features
    end

    test "returns all data features" do
      data_features = Features.by_category(:data)

      assert :data_export in data_features
      assert :bulk_import in data_features
    end

    test "returns all API features" do
      api_features = Features.by_category(:api)

      assert :api_access in api_features
      assert :webhooks in api_features
    end

    test "returns empty list for category with no features" do
      # Create a category that doesn't exist
      features = Features.by_category(:nonexistent_category)
      assert features == []
    end
  end

  describe "grouped_by_category/0" do
    test "returns features grouped by category" do
      grouped = Features.grouped_by_category()

      assert is_map(grouped)
      assert Map.has_key?(grouped, :ai)
      assert Map.has_key?(grouped, :data)
      assert Map.has_key?(grouped, :collaboration)
      assert Map.has_key?(grouped, :api)
      assert Map.has_key?(grouped, :customization)
      assert Map.has_key?(grouped, :support)

      # Verify each category has features
      assert is_list(grouped.ai)
      assert is_list(grouped.data)
      assert is_list(grouped.collaboration)
    end
  end

  describe "valid_feature?/1" do
    test "returns true for valid features" do
      assert Features.valid_feature?(:data_export)
      assert Features.valid_feature?(:api_access)
      assert Features.valid_feature?(:advanced_ai_models)
    end

    test "returns false for invalid features" do
      refute Features.valid_feature?(:invalid_feature)
      refute Features.valid_feature?(:not_a_feature)
    end
  end
end
