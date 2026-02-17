defmodule Citadel.Billing.AdvisoryLock do
  @moduledoc """
  PostgreSQL advisory locks for serializing credit operations.

  Uses transaction-scoped advisory locks (`pg_advisory_xact_lock`) to prevent
  race conditions when multiple processes attempt to modify credit balances
  for the same organization concurrently.

  The lock is automatically released when the transaction completes (commit or rollback).
  """

  alias Ecto.Adapters.SQL

  # Namespace derived from module name to avoid conflicts with other advisory locks.
  # Using phash2 of atom ensures deterministic value across restarts while being
  # unique to this module's purpose.
  @lock_namespace :erlang.phash2({__MODULE__, :credit_operations}, 2_147_483_647)

  @doc """
  Acquires a transaction-scoped advisory lock for credit operations on an organization.

  The lock uses a two-key approach:
  - First key: A namespace derived from this module to avoid conflicts with other advisory locks
  - Second key: A hash of the organization_id

  This function blocks until the lock is acquired. The lock is automatically
  released when the surrounding transaction completes.

  ## Example

      Citadel.Repo.transaction(fn ->
        AdvisoryLock.acquire_credit_lock!(organization_id)
        # ... perform credit operations ...
      end)
  """
  @spec acquire_credit_lock!(String.t()) :: :ok
  def acquire_credit_lock!(organization_id) when is_binary(organization_id) do
    lock_key = hash_organization_id(organization_id)

    SQL.query!(
      Citadel.Repo,
      "SELECT pg_advisory_xact_lock($1, $2)",
      [@lock_namespace, lock_key]
    )

    :ok
  end

  @doc """
  Executes a function with an advisory lock held for the given organization.

  Wraps the operation in a transaction if not already in one, acquires the lock,
  executes the function, and releases the lock when the transaction completes.

  ## Example

      AdvisoryLock.with_credit_lock(organization_id, fn ->
        # Safely read and update credit balance
        balance = get_latest_balance(organization_id)
        create_ledger_entry(organization_id, amount, balance + amount)
      end)
  """
  @spec with_credit_lock(String.t(), (-> result)) :: {:ok, result} | {:error, term()}
        when result: term()
  def with_credit_lock(organization_id, fun)
      when is_binary(organization_id) and is_function(fun, 0) do
    Citadel.Repo.transaction(fn ->
      acquire_credit_lock!(organization_id)
      fun.()
    end)
  end

  defp hash_organization_id(organization_id) do
    :erlang.phash2(organization_id, 2_147_483_647)
  end
end
