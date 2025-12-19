defmodule Citadel.Billing.Subscription.Changes.SetDefaultsForTier do
  @moduledoc """
  Sets appropriate defaults based on the subscription tier.

  - Free tier: billing_period is nil, seat_count defaults to 1
  - Pro tier: validates billing_period is set
  """
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    tier = Ash.Changeset.get_attribute(changeset, :tier)

    case tier do
      :free ->
        changeset
        |> Ash.Changeset.force_change_attribute(:billing_period, nil)
        |> Ash.Changeset.change_attribute(:seat_count, 1)

      :pro ->
        if is_nil(Ash.Changeset.get_attribute(changeset, :billing_period)) do
          Ash.Changeset.add_error(changeset,
            field: :billing_period,
            message: "is required for pro tier"
          )
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
