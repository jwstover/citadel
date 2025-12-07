defmodule Citadel.Tasks.Changes.InheritParentWorkspace do
  @moduledoc """
  Ensures sub-tasks inherit the workspace_id from their parent task.
  If a parent_task_id is provided, this change sets the workspace_id
  to match the parent task's workspace.
  """
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, %{tenant: tenant}) do
    if Ash.Changeset.changing_attribute?(changeset, :parent_task_id) do
      case Ash.Changeset.get_attribute(changeset, :parent_task_id) do
        nil ->
          changeset

        parent_task_id ->
          ensure_workspace_matches_parent(changeset, parent_task_id, tenant)
      end
    else
      changeset
    end
  end

  defp ensure_workspace_matches_parent(changeset, parent_task_id, tenant) do
    case Citadel.Tasks.Task
         |> Ash.Query.filter(id == ^parent_task_id)
         |> Ash.read_one(authorize?: false, tenant: tenant) do
      {:ok, %{workspace_id: workspace_id}} ->
        Ash.Changeset.force_change_attribute(changeset, :workspace_id, workspace_id)

      {:ok, nil} ->
        Ash.Changeset.add_error(changeset,
          field: :parent_task_id,
          message: "parent task not found"
        )

      {:error, _} ->
        Ash.Changeset.add_error(changeset,
          field: :parent_task_id,
          message: "parent task not found"
        )
    end
  end
end
