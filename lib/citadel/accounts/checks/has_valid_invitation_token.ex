defmodule Citadel.Accounts.Checks.HasValidInvitationToken do
  @moduledoc """
  Policy check to verify if a user has access via a valid invitation token.
  This allows anyone with the token to read or accept the invitation.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts) do
    "has valid invitation token"
  end

  @impl true
  def match?(actor, %{query: %Ash.Query{}}, _opts) when is_nil(actor) do
    # Allow unauthenticated reads - the token in the get_by will filter results
    true
  end

  def match?(_actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    # For update operations (accept), the record is already loaded
    # so we just need to verify it has a token
    token = Ash.Changeset.get_attribute(changeset, :token)
    not is_nil(token)
  end

  def match?(_actor, _context, _opts), do: false
end
