defmodule Citadel.Accounts.WorkspaceInvitation.Changes.ValidateInvitation do
  @moduledoc """
  Validates that an invitation can be accepted:
  - It must not be expired
  - It must not already be accepted
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    expires_at = Ash.Changeset.get_attribute(changeset, :expires_at)
    accepted_at = Ash.Changeset.get_attribute(changeset, :accepted_at)

    cond do
      not is_nil(accepted_at) ->
        {:error, field: :accepted_at, message: "This invitation has already been accepted"}

      not is_nil(expires_at) and DateTime.compare(expires_at, DateTime.utc_now()) == :lt ->
        {:error, field: :expires_at, message: "This invitation has expired"}

      true ->
        :ok
    end
  end
end
