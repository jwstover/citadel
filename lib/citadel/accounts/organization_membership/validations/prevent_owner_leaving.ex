defmodule Citadel.Accounts.OrganizationMembership.Validations.PreventOwnerLeaving do
  @moduledoc """
  Prevents the organization owner from leaving their organization.
  The owner must transfer ownership or delete the organization instead.
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    membership = changeset.data

    if membership.role == :owner do
      {:error, field: :role, message: "organization owner cannot leave the organization"}
    else
      :ok
    end
  end
end
