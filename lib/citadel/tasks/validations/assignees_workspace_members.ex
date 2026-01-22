defmodule Citadel.Tasks.Validations.AssigneesWorkspaceMembers do
  @moduledoc """
  Validates that all assignees are members of the task's workspace.

  Assignees must either be the workspace owner or have an active membership
  in the workspace.
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, context) do
    assignees = Ash.Changeset.get_argument(changeset, :assignees)

    if is_nil(assignees) or assignees == [] do
      :ok
    else
      workspace_id = get_workspace_id(changeset, context)

      if is_nil(workspace_id) do
        :ok
      else
        validate_assignees_are_members(assignees, workspace_id)
      end
    end
  end

  defp get_workspace_id(changeset, context) do
    Ash.Changeset.get_attribute(changeset, :workspace_id) ||
      get_workspace_id_from_parent(changeset, context)
  end

  defp get_workspace_id_from_parent(changeset, context) do
    case Ash.Changeset.get_attribute(changeset, :parent_task_id) do
      nil ->
        nil

      parent_task_id ->
        require Ash.Query

        case Citadel.Tasks.Task
             |> Ash.Query.filter(id == ^parent_task_id)
             |> Ash.Query.select([:workspace_id])
             |> Ash.read_one(authorize?: false, tenant: context.tenant) do
          {:ok, %{workspace_id: workspace_id}} -> workspace_id
          _ -> nil
        end
    end
  end

  defp validate_assignees_are_members(assignees, workspace_id) do
    valid_user_ids = get_workspace_member_ids(workspace_id)

    invalid_assignees =
      Enum.reject(assignees, fn assignee_id ->
        assignee_id in valid_user_ids
      end)

    if invalid_assignees == [] do
      :ok
    else
      {:error, field: :assignees, message: "all assignees must be members of the workspace"}
    end
  end

  defp get_workspace_member_ids(workspace_id) do
    require Ash.Query

    workspace =
      Citadel.Accounts.Workspace
      |> Ash.Query.filter(id == ^workspace_id)
      |> Ash.Query.load([:owner_id, memberships: [:user_id]])
      |> Ash.read_one!(authorize?: false)

    member_ids =
      workspace.memberships
      |> Enum.map(& &1.user_id)

    [workspace.owner_id | member_ids]
  end
end
