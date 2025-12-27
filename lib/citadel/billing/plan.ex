defmodule Citadel.Billing.Plan do
  @moduledoc """
  Plan configuration for subscription tiers.

  This module provides a centralized location for all plan limits and Stripe price IDs.
  It is NOT a database resource - these values are defined in code for type safety
  and to avoid database lookups for frequently accessed configuration.

  ## Adding New Tiers

  To add a new tier, simply add an entry to the `@plans` map below. The tier will
  automatically be available throughout the system. You'll also need to:
  1. Add the tier atom to the `Tier` enum type
  2. Configure Stripe price IDs in runtime config (if paid tier)

  ## Tier Categories

  - `:free` - No billing period required, no seat pricing
  - `:paid` - Requires billing period, supports seat-based pricing

  ## Pricing

  | Tier | Base Price | Per Member | Credits/Month | Workspaces | Members |
  |------|------------|------------|---------------|------------|---------|
  | Free | $0 | - | 500 | 1 | 1 (solo only) |
  | Pro (Monthly) | $19/mo | +$5/member | 10,000 (shared) | 5 | 5 |
  | Pro (Annual) | $190/yr | +$50/member/yr | 10,000 (shared) | 5 | 5 |
  """

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
      monthly_credits: 500,
      max_workspaces: 1,
      max_members: 1,
      allows_byok: false,
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
      %{name: "Free", monthly_credits: 500, ...}
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
  """
  @spec allows_byok?(tier()) :: boolean()
  def allows_byok?(tier), do: get(tier).allows_byok

  @doc """
  Checks if a tier is valid.
  """
  @spec valid_tier?(atom()) :: boolean()
  def valid_tier?(tier), do: tier in @valid_tiers
end
