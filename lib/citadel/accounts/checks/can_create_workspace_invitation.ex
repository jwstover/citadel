defmodule Citadel.Accounts.Checks.CanCreateWorkspaceInvitation do
  @moduledoc """
  Policy check to verify if the actor can create invitations for a workspace.
  The actor must be either the workspace owner or an existing member.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts) do
    "actor can create workspace invitations"
  end

  @impl true
  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) when not is_nil(actor) do
    # workspace_id is an accepted attribute, not an argument
    workspace_id =
      Ash.Changeset.get_attribute(changeset, :workspace_id) ||
        Ash.Changeset.get_argument(changeset, :workspace_id)

    actor_id = Map.get(actor, :id)

    if is_nil(workspace_id) or is_nil(actor_id) do
      false
    else
      owner_or_member?(actor_id, workspace_id)
    end
  end

  def match?(_actor, _context, _opts), do: false

  # sobelow_skip ["SQL.Query"]
  defp owner_or_member?(actor_id, workspace_id) do
    # Use raw SQL query to check if actor is owner or member
    # This is safe because we use parameterized queries ($1, $2)
    # Convert string UUIDs to binary format for Postgres
    {:ok, workspace_bin} = Ecto.UUID.dump(workspace_id)
    {:ok, actor_bin} = Ecto.UUID.dump(actor_id)

    query = """
    SELECT EXISTS(
      SELECT 1 FROM workspaces WHERE id = $1 AND owner_id = $2
    ) OR EXISTS(
      SELECT 1 FROM workspace_memberships WHERE workspace_id = $1 AND user_id = $2
    )
    """

    case Citadel.Repo.query(query, [workspace_bin, actor_bin]) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  end
end
