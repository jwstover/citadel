defmodule Citadel.Accounts.Checks.WorkspaceMember do
  @moduledoc """
  Policy check to verify if the actor is a member of the workspace.
  """
  use Ash.Policy.FilterCheck

  @impl true
  def describe(_opts) do
    "actor is a workspace member"
  end

  @impl true
  def filter(_actor, _context, _opts) do
    import Ash.Expr

    # Check if the actor has a membership in this workspace
    expr(exists(memberships, user_id == ^actor(:id)))
  end
end
