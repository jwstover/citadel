defmodule Citadel.Accounts.OrganizationMembership.Changes.EnqueueSeatSync do
  @moduledoc """
  Enqueues a seat sync job after membership changes.

  This change is added to the `join` and `leave` actions on OrganizationMembership.
  It runs in `after_transaction` to ensure the membership change is committed
  before we attempt to sync with Stripe.

  The worker uses Oban's unique job feature to deduplicate rapid membership
  changes, so multiple adds/removes within 60 seconds will only trigger one
  Stripe API call.
  """
  use Ash.Resource.Change

  alias Citadel.Workers.SyncSeatCountWorker

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, result} ->
        org_id = get_organization_id(changeset, result)
        enqueue_sync(org_id)
        {:ok, result}

      _changeset, {:error, error} ->
        {:error, error}
    end)
  end

  defp get_organization_id(changeset, result) do
    # For create actions, get from the result
    # For destroy actions, get from the changeset data
    case result do
      %{organization_id: org_id} when is_binary(org_id) ->
        org_id

      _ ->
        # Destroy returns the deleted record, but we can also check changeset
        Ash.Changeset.get_attribute(changeset, :organization_id)
    end
  end

  defp enqueue_sync(nil), do: :ok

  defp enqueue_sync(org_id) do
    %{organization_id: org_id}
    |> SyncSeatCountWorker.new()
    |> Oban.insert()

    :ok
  end
end
