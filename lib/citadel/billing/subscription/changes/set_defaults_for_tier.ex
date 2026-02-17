defmodule Citadel.Billing.Subscription.Changes.SetDefaultsForTier do
  @moduledoc """
  Sets appropriate defaults based on the subscription tier configuration.

  Uses the Plan module to determine tier behavior:
  - Free tiers: billing_period is cleared, seat_count defaults to 1
  - Paid tiers: validates billing_period is set
  """
  use Ash.Resource.Change

  alias Citadel.Billing.Plan

  def change(changeset, _opts, _context) do
    tier = Ash.Changeset.get_attribute(changeset, :tier)

    if Plan.valid_tier?(tier) do
      changeset
      |> maybe_clear_billing_period(tier)
      |> maybe_set_default_seats(tier)
      |> validate_billing_period(tier)
    else
      Ash.Changeset.add_error(changeset,
        field: :tier,
        message: "is not a valid tier"
      )
    end
  end

  defp maybe_clear_billing_period(changeset, tier) do
    if Plan.requires_billing_period?(tier) do
      changeset
    else
      Ash.Changeset.force_change_attribute(changeset, :billing_period, nil)
    end
  end

  defp maybe_set_default_seats(changeset, tier) do
    if Plan.allows_seats?(tier) do
      changeset
    else
      Ash.Changeset.change_attribute(changeset, :seat_count, 1)
    end
  end

  defp validate_billing_period(changeset, tier) do
    if Plan.requires_billing_period?(tier) and
         is_nil(Ash.Changeset.get_attribute(changeset, :billing_period)) do
      Ash.Changeset.add_error(changeset,
        field: :billing_period,
        message: "is required for #{tier} tier"
      )
    else
      changeset
    end
  end
end
