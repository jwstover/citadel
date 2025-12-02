defmodule Citadel.Accounts.Checks.CanManageWorkspaceMembership do
  @moduledoc """
  Policy check to verify if the actor can manage memberships for a workspace.
  The actor must be either the workspace owner or an existing member.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts) do
    "actor can manage workspace memberships"
  end

  @impl true
  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    # workspace_id can be either an argument or an attribute
    workspace_id =
      Ash.Changeset.get_argument(changeset, :workspace_id) ||
        Ash.Changeset.get_attribute(changeset, :workspace_id)

    if is_nil(workspace_id) do
      false
    else
      check_can_manage(actor, workspace_id)
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp check_can_manage(actor, workspace_id) when not is_nil(actor) do
    require Ash.Query

    actor_id = Map.get(actor, :id)

    if is_nil(actor_id) do
      false
    else
      # Check if actor is the workspace owner or a member
      result =
        Citadel.Accounts.Workspace
        |> Ash.Query.filter(id == ^workspace_id)
        |> Ash.read_one(authorize?: false)

      case result do
        {:ok, workspace} when not is_nil(workspace) ->
          workspace_owner?(workspace, actor_id) or workspace_member?(workspace_id, actor_id)

        _ ->
          false
      end
    end
  end

  defp check_can_manage(_actor, _workspace_id), do: false

  defp workspace_owner?(workspace, actor_id) do
    workspace.owner_id == actor_id
  end

  defp workspace_member?(workspace_id, actor_id) do
    require Ash.Query

    case Citadel.Accounts.WorkspaceMembership
         |> Ash.Query.filter(workspace_id == ^workspace_id and user_id == ^actor_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, membership} when not is_nil(membership) -> true
      _ -> false
    end
  end
end
