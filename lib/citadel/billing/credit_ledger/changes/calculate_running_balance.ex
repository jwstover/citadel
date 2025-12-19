defmodule Citadel.Billing.CreditLedger.Changes.CalculateRunningBalance do
  @moduledoc """
  Calculates the running balance for a credit ledger entry by getting
  the previous balance and adding the current transaction amount.
  """
  use Ash.Resource.Change

  require Ash.Query

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
      amount = Ash.Changeset.get_attribute(changeset, :amount) || 0

      previous_balance = get_latest_balance(organization_id) || 0
      new_balance = previous_balance + amount

      Ash.Changeset.force_change_attribute(changeset, :running_balance, new_balance)
    end)
  end

  defp get_latest_balance(organization_id) when is_binary(organization_id) do
    Citadel.Billing.CreditLedger
    |> Ash.Query.filter(organization_id == ^organization_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.Query.select([:running_balance])
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> nil
      entry -> entry.running_balance
    end
  end

  defp get_latest_balance(_), do: nil
end
