defmodule Citadel.Accounts.WorkspaceMembership.Changes.PreventOwnerLeaving do
  @moduledoc """
  Validation to prevent workspace owners from leaving their own workspace.
  Owners must transfer ownership before they can leave.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    # Get the IDs directly since the relationships might not be loaded
    workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)
    user_id = Ash.Changeset.get_attribute(changeset, :user_id)

    if is_nil(workspace_id) or is_nil(user_id) do
      :ok
    else
      check_owner_leaving(workspace_id, user_id)
    end
  end

  defp check_owner_leaving(workspace_id, user_id) do
    # Load the workspace to check if the user is the owner
    case Citadel.Accounts.Workspace
         |> Ash.Query.filter(id == ^workspace_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, workspace} when not is_nil(workspace) ->
        validate_owner(workspace, user_id)

      _ ->
        :ok
    end
  end

  defp validate_owner(workspace, user_id) do
    if workspace.owner_id == user_id do
      {:error,
       field: :user_id,
       message: "Workspace owner cannot leave their own workspace. Transfer ownership first."}
    else
      :ok
    end
  end
end
