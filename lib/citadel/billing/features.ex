defmodule Citadel.Billing.Features do
  @moduledoc """
  Feature catalog with metadata for subscription billing features.

  This module defines features tied to subscription tiers for billing purposes.
  This is separate from operational feature flags, which can use any atom key.

  ## Subscription Features vs Feature Flags

  - **This catalog**: Product features tied to subscription tiers (billing)
  - **Feature flags** (`Citadel.Settings.FeatureFlag`): Operational controls with any key
  - **Override behavior**: When a flag key matches a feature here, flag overrides tier access

  ## Feature Categories

  - `:ai` - AI model access and capabilities
  - `:collaboration` - Team and workspace features
  - `:data` - Import/export and data management
  - `:customization` - Branding and appearance
  - `:support` - Support tiers and SLAs
  - `:api` - API access and integrations

  ## Usage

      # Get feature metadata
      Features.get(:data_export)
      #=> %{name: "Data Export", description: "...", category: :data, type: :binary}

      # Get display name
      Features.name(:data_export)
      #=> "Data Export"

      # List all features in a category
      Features.by_category(:ai)
      #=> [:basic_ai, :advanced_ai_models, :byok]

  ## Adding New Features

  To add a new feature:
  1. Add the feature atom with metadata to `@features` map below
  2. Add the feature to appropriate tier(s) in `Citadel.Billing.Plan`
  3. Use `HasFeature` policy check to gate the feature in resources
  4. Use feature helpers in LiveViews for UI checks
  """

  @type feature :: atom()
  @type category :: :ai | :collaboration | :data | :customization | :support | :api
  @type feature_type :: :binary

  @features %{
    # AI Features
    basic_ai: %{
      name: "Basic AI Models",
      description: "Access to standard AI models for chat and task generation",
      category: :ai,
      type: :binary
    },
    advanced_ai_models: %{
      name: "Advanced AI Models",
      description: "Access to Claude Opus and other premium AI models",
      category: :ai,
      type: :binary
    },
    byok: %{
      name: "Bring Your Own Key",
      description: "Use your own Anthropic or OpenAI API keys for unlimited AI usage",
      category: :ai,
      type: :binary
    },
    # Collaboration Features
    multiple_workspaces: %{
      name: "Multiple Workspaces",
      description: "Create and manage up to 5 workspaces",
      category: :collaboration,
      type: :binary
    },
    team_collaboration: %{
      name: "Team Collaboration",
      description: "Invite up to 5 team members to your organization",
      category: :collaboration,
      type: :binary
    },
    # Data Features
    data_export: %{
      name: "Data Export",
      description: "Export your tasks and conversations in CSV/JSON format",
      category: :data,
      type: :binary
    },
    bulk_import: %{
      name: "Bulk Import",
      description: "Import tasks from external project management tools",
      category: :data,
      type: :binary
    },
    # API Features
    api_access: %{
      name: "API Access",
      description: "Programmatic access to your data via REST API",
      category: :api,
      type: :binary
    },
    webhooks: %{
      name: "Webhooks",
      description: "Real-time webhooks for task and conversation events",
      category: :api,
      type: :binary
    },
    # Customization Features
    custom_branding: %{
      name: "Custom Branding",
      description: "Customize workspace colors, logos, and themes",
      category: :customization,
      type: :binary
    },
    # Support Features
    priority_support: %{
      name: "Priority Support",
      description: "Priority email support with faster response times",
      category: :support,
      type: :binary
    }
  }

  @valid_features Map.keys(@features)

  @doc """
  Returns metadata for a feature.

  ## Examples

      iex> Citadel.Billing.Features.get(:data_export)
      %{
        name: "Data Export",
        description: "Export your tasks and conversations in CSV/JSON format",
        category: :data,
        type: :binary
      }

      iex> Citadel.Billing.Features.get(:invalid_feature)
      nil
  """
  @spec get(feature()) :: map() | nil
  def get(feature) when feature in @valid_features do
    Map.get(@features, feature)
  end

  def get(_feature), do: nil

  @doc """
  Returns the display name for a feature.

  ## Examples

      iex> Citadel.Billing.Features.name(:data_export)
      "Data Export"
  """
  @spec name(feature()) :: String.t()
  def name(feature) do
    case get(feature) do
      nil -> to_string(feature)
      metadata -> metadata.name
    end
  end

  @doc """
  Returns the description for a feature.

  ## Examples

      iex> Citadel.Billing.Features.description(:data_export)
      "Export your tasks and conversations in CSV/JSON format"
  """
  @spec description(feature()) :: String.t()
  def description(feature) do
    case get(feature) do
      nil -> ""
      metadata -> metadata.description
    end
  end

  @doc """
  Returns the category for a feature.

  ## Examples

      iex> Citadel.Billing.Features.category(:data_export)
      :data
  """
  @spec category(feature()) :: category() | nil
  def category(feature) do
    case get(feature) do
      nil -> nil
      metadata -> metadata.category
    end
  end

  @doc """
  Lists all available features.

  ## Examples

      iex> Citadel.Billing.Features.list_all()
      [:basic_ai, :advanced_ai_models, :byok, ...]
  """
  @spec list_all() :: [feature()]
  def list_all, do: @valid_features

  @doc """
  Lists features in a specific category.

  ## Examples

      iex> Citadel.Billing.Features.by_category(:ai)
      [:basic_ai, :advanced_ai_models, :byok]
  """
  @spec by_category(category()) :: [feature()]
  def by_category(category) do
    Enum.filter(@valid_features, fn feature ->
      get(feature).category == category
    end)
  end

  @doc """
  Returns all features grouped by category.

  ## Examples

      iex> Citadel.Billing.Features.grouped_by_category()
      %{
        ai: [:basic_ai, :advanced_ai_models, :byok],
        collaboration: [:multiple_workspaces, :team_collaboration],
        ...
      }
  """
  @spec grouped_by_category() :: %{category() => [feature()]}
  def grouped_by_category do
    Enum.group_by(@valid_features, fn feature ->
      get(feature).category
    end)
  end

  @doc """
  Checks if a feature key is valid.

  ## Examples

      iex> Citadel.Billing.Features.valid_feature?(:data_export)
      true

      iex> Citadel.Billing.Features.valid_feature?(:invalid_feature)
      false
  """
  @spec valid_feature?(atom()) :: boolean()
  def valid_feature?(feature), do: feature in @valid_features
end
