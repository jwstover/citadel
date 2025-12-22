defmodule Citadel.Billing.Plan do
  @moduledoc """
  Plan configuration for subscription tiers.

  This module provides a centralized location for all plan limits and Stripe price IDs.
  It is NOT a database resource - these values are defined in code for type safety
  and to avoid database lookups for frequently accessed configuration.

  ## Pricing

  | Tier | Base Price | Per Member | Credits/Month | Workspaces |
  |------|------------|------------|---------------|------------|
  | Free | $0 | - | 500 | 1 (solo only) |
  | Pro (Monthly) | $19/mo | +$5/member | 10,000 (shared) | 5 |
  | Pro (Annual) | $190/yr | +$50/member/yr | 10,000 (shared) | 5 |
  """

  @type tier :: :free | :pro
  @type billing_period :: :monthly | :annual

  @plans %{
    free: %{
      name: "Free",
      monthly_price_cents: 0,
      annual_price_cents: 0,
      per_member_monthly_cents: 0,
      per_member_annual_cents: 0,
      monthly_credits: 500,
      max_workspaces: 1,
      max_members_per_workspace: 1,
      stripe_monthly_price_id: nil,
      stripe_annual_price_id: nil,
      stripe_seat_monthly_price_id: nil,
      stripe_seat_annual_price_id: nil
    },
    pro: %{
      name: "Pro",
      monthly_price_cents: 1900,
      annual_price_cents: 19_000,
      per_member_monthly_cents: 500,
      per_member_annual_cents: 5000,
      monthly_credits: 10_000,
      max_workspaces: 5,
      max_members_per_workspace: :unlimited,
      stripe_monthly_price_id: nil,
      stripe_annual_price_id: nil,
      stripe_seat_monthly_price_id: nil,
      stripe_seat_annual_price_id: nil
    }
  }

  # Maps tier atoms to their config key atoms
  @tier_config_keys %{
    free: %{
      monthly: :free_monthly_price_id,
      annual: :free_annual_price_id,
      seat_monthly: :free_seat_monthly_price_id,
      seat_annual: :free_seat_annual_price_id
    },
    pro: %{
      monthly: :pro_monthly_price_id,
      annual: :pro_annual_price_id,
      seat_monthly: :pro_seat_monthly_price_id,
      seat_annual: :pro_seat_annual_price_id
    }
  }

  @doc """
  Gets the plan configuration for a tier.

  ## Examples

      iex> Citadel.Billing.Plan.get(:free)
      %{name: "Free", monthly_credits: 500, ...}
  """
  @spec get(tier()) :: map()
  def get(tier) when tier in [:free, :pro] do
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
  Gets the maximum members per workspace for a tier.
  Returns :unlimited for Pro tier.
  """
  @spec max_members_per_workspace(tier()) :: integer() | :unlimited
  def max_members_per_workspace(tier) do
    get(tier).max_members_per_workspace
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
  Checks if a tier allows a given number of workspace members.
  """
  @spec allows_member_count?(tier(), integer()) :: boolean()
  def allows_member_count?(tier, count) do
    case max_members_per_workspace(tier) do
      :unlimited -> true
      max -> count <= max
    end
  end

  @doc """
  Lists all available tiers.
  """
  @spec list_tiers() :: [tier()]
  def list_tiers, do: [:free, :pro]
end
