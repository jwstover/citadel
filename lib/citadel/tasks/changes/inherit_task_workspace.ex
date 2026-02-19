defmodule Citadel.Tasks.Changes.InheritTaskWorkspace do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, %{tenant: tenant}) do
    case Ash.Changeset.get_attribute(changeset, :task_id) do
      nil ->
        changeset

      task_id ->
        set_workspace_from_task(changeset, task_id, tenant)
    end
  end

  defp set_workspace_from_task(changeset, task_id, tenant) do
    case Citadel.Tasks.Task
         |> Ash.Query.filter(id == ^task_id)
         |> Ash.read_one(authorize?: false, tenant: tenant) do
      {:ok, %{workspace_id: workspace_id}} ->
        Ash.Changeset.force_change_attribute(changeset, :workspace_id, workspace_id)

      {:ok, nil} ->
        Ash.Changeset.add_error(changeset,
          field: :task_id,
          message: "task not found"
        )

      {:error, _} ->
        Ash.Changeset.add_error(changeset,
          field: :task_id,
          message: "task not found"
        )
    end
  end
end
