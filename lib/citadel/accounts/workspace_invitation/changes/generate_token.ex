defmodule Citadel.Accounts.WorkspaceInvitation.Changes.GenerateToken do
  @moduledoc """
  Generates a secure random token for workspace invitations.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    # Only generate token if not already provided
    if Ash.Changeset.get_attribute(changeset, :token) do
      changeset
    else
      token = generate_secure_token()
      Ash.Changeset.force_change_attribute(changeset, :token, token)
    end
  end

  defp generate_secure_token do
    # Generate a URL-safe base64 encoded token
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end
end
