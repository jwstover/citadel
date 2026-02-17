defmodule Citadel.Billing.Plan do
  @moduledoc """
  Plan configuration for subscription tiers.

  This module provides a centralized location for all plan limits, Stripe price IDs,
  and feature availability. It is NOT a database resource - these values are defined
  in code for type safety and to avoid database lookups for frequently accessed configuration.

  ## Adding New Tiers

  To add a new tier, simply add an entry to the `@plans` map below. The tier will
  automatically be available throughout the system. You'll also need to:
  1. Add the tier atom to the `Tier` enum type
  2. Configure Stripe price IDs in runtime config (if paid tier)
  3. Define which features are available for the tier

  ## Tier Categories

  - `:free` - No billing period required, no seat pricing
  - `:paid` - Requires billing period, supports seat-based pricing

  ## Feature System

  Features are defined per tier and can be queried in multiple ways:

      # Check if a tier has a feature
      Plan.tier_has_feature?(:pro, :data_export)

      # Check if an organization has a feature (respects global flags)
      Plan.org_has_feature?(org_id, :api_access)

      # Get all features for a tier
      Plan.features_for_tier(:pro)

  See `Citadel.Billing.Features` for the feature catalog with metadata.

  ## Feature Flags Override

  Global feature flags (`Citadel.Settings.FeatureFlag`) can override tier features:
  - When a flag key matches a billing feature → flag value overrides tier access
  - When a flag key doesn't match billing → flag value used directly (operational control)
  - Feature flags enable gradual rollouts, killswitches, and beta features

  ## Adding New Features

  1. Define feature in `Citadel.Billing.Features`
  2. Add feature atom to tier's `features` MapSet in `@plans`
  3. Use `HasFeature` policy check to gate the feature
  4. Use `FeatureHelpers` in LiveViews for UI checks

  ## Pricing

  | Tier | Base Price | Per Member | Credits/Month | Workspaces | Members |
  |------|------------|------------|---------------|------------|---------|
  | Free | $0 | - | 1000 | 1 | 1 (solo only) |
  | Pro (Monthly) | $19/mo | +$5/member | 10,000 (shared) | 5 | 5 |
  | Pro (Annual) | $190/yr | +$50/member/yr | 10,000 (shared) | 5 | 5 |
  """

  alias Citadel.Settings.FeatureFlags

  @type tier :: :free | :pro
  @type billing_period :: :monthly | :annual

  @plans %{
    free: %{
      name: "Free",
      category: :free,
      requires_billing_period: false,
      allows_seats: false,
      monthly_price_cents: 0,
      annual_price_cents: 0,
      per_member_monthly_cents: 0,
      per_member_annual_cents: 0,
      monthly_credits: 1000,
      max_workspaces: 1,
      max_members: 1,
      allows_byok: false,
      features:
        MapSet.new([
          :basic_ai
        ]),
      stripe_monthly_price_id: nil,
      stripe_annual_price_id: nil,
      stripe_seat_monthly_price_id: nil,
      stripe_seat_annual_price_id: nil
    },
    pro: %{
      name: "Pro",
      category: :paid,
      requires_billing_period: true,
      allows_seats: true,
      monthly_price_cents: 1900,
      annual_price_cents: 19_000,
      per_member_monthly_cents: 500,
      per_member_annual_cents: 5000,
      monthly_credits: 10_000,
      max_workspaces: 5,
      max_members: 5,
      allows_byok: true,
      features:
        MapSet.new([
          :basic_ai,
          :advanced_ai_models,
          :byok,
          :multiple_workspaces,
          :team_collaboration,
          :data_export,
          :bulk_import,
          :api_access,
          :webhooks,
          :custom_branding,
          :priority_support
        ]),
      stripe_monthly_price_id: nil,
      stripe_annual_price_id: nil,
      stripe_seat_monthly_price_id: nil,
      stripe_seat_annual_price_id: nil
    }
  }

  @valid_tiers Map.keys(@plans)

  # Auto-generate config keys for each tier
  @tier_config_keys Map.new(@valid_tiers, fn tier ->
                      {tier,
                       %{
                         monthly: :"#{tier}_monthly_price_id",
                         annual: :"#{tier}_annual_price_id",
                         seat_monthly: :"#{tier}_seat_monthly_price_id",
                         seat_annual: :"#{tier}_seat_annual_price_id"
                       }}
                    end)

  @doc """
  Gets the plan configuration for a tier.

  ## Examples

      iex> Citadel.Billing.Plan.get(:free)
      %{name: "Free", monthly_credits: 1000, ...}
  """
  @spec get(tier()) :: map()
  def get(tier) when tier in @valid_tiers do
    base_plan = Map.get(@plans, tier)
    config = Application.get_env(:citadel, Citadel.Billing, [])
    keys = Map.fetch!(@tier_config_keys, tier)

    base_plan
    |> maybe_override(:stripe_monthly_price_id, config[keys.monthly])
    |> maybe_override(:stripe_annual_price_id, config[keys.annual])
    |> maybe_override(:stripe_seat_monthly_price_id, config[keys.seat_monthly])
    |> maybe_override(:stripe_seat_annual_price_id, config[keys.seat_annual])
  end

  defp maybe_override(plan, _key, nil), do: plan
  defp maybe_override(plan, key, value), do: Map.put(plan, key, value)

  @doc """
  Gets the monthly credit allocation for a tier.
  """
  @spec monthly_credits(tier()) :: integer()
  def monthly_credits(tier) do
    get(tier).monthly_credits
  end

  @doc """
  Gets the maximum number of workspaces allowed for a tier.
  """
  @spec max_workspaces(tier()) :: integer()
  def max_workspaces(tier) do
    get(tier).max_workspaces
  end

  @doc """
  Gets the maximum members allowed per organization for a tier.
  """
  @spec max_members(tier()) :: integer()
  def max_members(tier) do
    get(tier).max_members
  end

  @doc """
  Gets the base price in cents for a tier and billing period.
  """
  @spec base_price_cents(tier(), billing_period()) :: integer()
  def base_price_cents(tier, :monthly), do: get(tier).monthly_price_cents
  def base_price_cents(tier, :annual), do: get(tier).annual_price_cents

  @doc """
  Gets the per-member price in cents for a tier and billing period.
  """
  @spec per_member_price_cents(tier(), billing_period()) :: integer()
  def per_member_price_cents(tier, :monthly), do: get(tier).per_member_monthly_cents
  def per_member_price_cents(tier, :annual), do: get(tier).per_member_annual_cents

  @doc """
  Gets the Stripe price ID for a tier's base subscription.
  """
  @spec stripe_price_id(tier(), billing_period()) :: String.t() | nil
  def stripe_price_id(tier, :monthly), do: get(tier).stripe_monthly_price_id
  def stripe_price_id(tier, :annual), do: get(tier).stripe_annual_price_id

  @doc """
  Gets the Stripe price ID for additional seats.
  """
  @spec stripe_seat_price_id(tier(), billing_period()) :: String.t() | nil
  def stripe_seat_price_id(tier, :monthly), do: get(tier).stripe_seat_monthly_price_id
  def stripe_seat_price_id(tier, :annual), do: get(tier).stripe_seat_annual_price_id

  @doc """
  Checks if a tier allows a given number of workspaces.
  """
  @spec allows_workspace_count?(tier(), integer()) :: boolean()
  def allows_workspace_count?(tier, count) do
    count <= max_workspaces(tier)
  end

  @doc """
  Checks if a tier allows a given number of organization members.
  """
  @spec allows_member_count?(tier(), integer()) :: boolean()
  def allows_member_count?(tier, count) do
    count <= max_members(tier)
  end

  @doc """
  Lists all available tiers.
  """
  @spec list_tiers() :: [tier()]
  def list_tiers, do: @valid_tiers

  @doc """
  Returns the default tier for new organizations.
  """
  @spec default_tier() :: tier()
  def default_tier, do: :free

  @doc """
  Lists all paid tiers (those with category :paid).
  """
  @spec paid_tiers() :: [tier()]
  def paid_tiers do
    Enum.filter(@valid_tiers, fn tier -> get(tier).category == :paid end)
  end

  @doc """
  Lists all free tiers (those with category :free).
  """
  @spec free_tiers() :: [tier()]
  def free_tiers do
    Enum.filter(@valid_tiers, fn tier -> get(tier).category == :free end)
  end

  @doc """
  Checks if a tier is a paid tier.
  """
  @spec paid_tier?(tier()) :: boolean()
  def paid_tier?(tier), do: get(tier).category == :paid

  @doc """
  Checks if a tier requires a billing period.
  """
  @spec requires_billing_period?(tier()) :: boolean()
  def requires_billing_period?(tier), do: get(tier).requires_billing_period

  @doc """
  Checks if a tier allows seat-based pricing.
  """
  @spec allows_seats?(tier()) :: boolean()
  def allows_seats?(tier), do: get(tier).allows_seats

  @doc """
  Checks if a tier allows BYOK (Bring Your Own Key).

  This delegates to the feature system for consistency.
  """
  @spec allows_byok?(tier()) :: boolean()
  def allows_byok?(tier), do: tier_has_feature?(tier, :byok)

  @doc """
  Checks if a tier is valid.
  """
  @spec valid_tier?(atom()) :: boolean()
  def valid_tier?(tier), do: tier in @valid_tiers

  # Feature System Functions

  @doc """
  Gets the set of features available for a tier.

  ## Examples

      iex> Citadel.Billing.Plan.features(:pro)
      #MapSet<[:basic_ai, :advanced_ai_models, :data_export, ...]>
  """
  @spec features(tier()) :: MapSet.t(atom())
  def features(tier) do
    get(tier).features
  end

  @doc """
  Checks if a tier has access to a specific feature.

  ## Examples

      iex> Citadel.Billing.Plan.tier_has_feature?(:pro, :data_export)
      true

      iex> Citadel.Billing.Plan.tier_has_feature?(:free, :data_export)
      false
  """
  @spec tier_has_feature?(tier(), atom()) :: boolean()
  def tier_has_feature?(tier, feature) do
    MapSet.member?(features(tier), feature)
  end

  @doc """
  Checks if an organization has access to a specific feature.

  Checks global feature flags first, then falls back to subscription tier features.
  This allows global flags to override tier-based feature access.

  ## Priority Order

  1. Global feature flags (checked via ETS cache)
  2. Subscription tier features (if no flag exists)

  ## Graceful Degradation

  - If cache lookup fails, falls back to tier check
  - If subscription lookup fails, returns the error

  ## Examples

      iex> Citadel.Billing.Plan.org_has_feature?(org_id, :api_access)
      {:ok, true}

      iex> Citadel.Billing.Plan.org_has_feature?(org_id, :advanced_ai_models)
      {:ok, false}
  """
  @spec org_has_feature?(Ash.UUID.t(), atom()) :: {:ok, boolean()} | {:error, term()}
  def org_has_feature?(organization_id, feature) do
    # Check global feature flags first
    case FeatureFlags.get(feature) do
      {:ok, enabled} ->
        {:ok, enabled}

      :not_found ->
        # Fall back to tier-based feature check
        case Citadel.Billing.get_subscription_by_organization(organization_id, authorize?: false) do
          {:ok, subscription} ->
            {:ok, tier_has_feature?(subscription.tier, feature)}

          {:error, _} = error ->
            error
        end
    end
  end

  @doc """
  Returns a list of features available for a tier.

  Useful for UI display on pricing/features pages.

  ## Examples

      iex> Citadel.Billing.Plan.features_for_tier(:pro)
      [:basic_ai, :advanced_ai_models, :data_export, ...]
  """
  @spec features_for_tier(tier()) :: [atom()]
  def features_for_tier(tier) do
    features(tier) |> MapSet.to_list()
  end

  @doc """
  Returns a map of tier => features for all tiers.

  Useful for comparison tables on pricing pages.

  ## Examples

      iex> Citadel.Billing.Plan.all_tier_features()
      %{free: [:basic_ai], pro: [:basic_ai, :advanced_ai_models, ...]}
  """
  @spec all_tier_features() :: %{tier() => [atom()]}
  def all_tier_features do
    Map.new(@valid_tiers, fn tier ->
      {tier, features_for_tier(tier)}
    end)
  end
end
