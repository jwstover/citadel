defmodule Citadel.Repo.Migrations.AddCreditBalanceCheckConstraint do
  @moduledoc """
  Adds a CHECK constraint to prevent negative credit balances.

  This provides defense-in-depth against TOCTOU race conditions by enforcing
  at the database level that running_balance can never go negative.
  """

  use Ecto.Migration

  def up do
    create constraint(:credit_ledger, :running_balance_non_negative,
             check: "running_balance >= 0"
           )
  end

  def down do
    drop constraint(:credit_ledger, :running_balance_non_negative)
  end
end
