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
    workspace_id = Ash.Changeset.get_argument(changeset, :workspace_id)

    if is_nil(workspace_id) do
      false
    else
      check_can_manage(actor, workspace_id)
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp check_can_manage(actor, workspace_id) when not is_nil(actor) do
    require Ash.Query

    # Check if actor is the workspace owner or a member
    workspace =
      Citadel.Accounts.Workspace
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(id == ^workspace_id)
      |> Ash.Query.load(:memberships)
      |> Ash.read_one(authorize?: false)

    case workspace do
      {:ok, workspace} when not is_nil(workspace) ->
        is_owner = workspace.owner_id == actor.id

        is_member =
          Enum.any?(workspace.memberships || [], fn membership ->
            membership.user_id == actor.id
          end)

        is_owner or is_member

      _ ->
        false
    end
  end

  defp check_can_manage(_actor, _workspace_id), do: false
end
