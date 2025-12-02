defmodule Citadel.Accounts.WorkspaceInvitation.Changes.SetExpiration do
  @moduledoc """
  Sets the expiration date to 7 days from now for workspace invitations.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    # Only set expiration if not already provided
    if Ash.Changeset.get_attribute(changeset, :expires_at) do
      changeset
    else
      expires_at = DateTime.add(DateTime.utc_now(), 7, :day)
      Ash.Changeset.force_change_attribute(changeset, :expires_at, expires_at)
    end
  end
end
