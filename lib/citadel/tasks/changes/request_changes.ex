defmodule Citadel.Tasks.Changes.RequestChanges do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, activity ->
      create_work_item(activity)
      transition_task_to_in_progress(activity)
      {:ok, activity}
    end)
  end

  defp create_work_item(activity) do
    Citadel.Tasks.AgentWorkItem
    |> Ash.Changeset.for_create(
      :create,
      %{type: :changes_requested, task_id: activity.task_id, comment_id: activity.id},
      authorize?: false,
      tenant: activity.workspace_id
    )
    |> Ash.create()
    |> case do
      {:ok, _work_item} -> :ok
      {:error, _} -> :ok
    end
  end

  defp transition_task_to_in_progress(activity) do
    with {:ok, task} <- get_task(activity),
         true <- in_review?(task.task_state_id),
         {:ok, in_progress_state} <- get_in_progress_state() do
      task
      |> Ash.Changeset.for_update(:update, %{task_state_id: in_progress_state.id},
        authorize?: false,
        tenant: activity.workspace_id
      )
      |> Ash.update()
    end

    :ok
  end

  defp get_task(activity) do
    Citadel.Tasks.Task
    |> Ash.Query.filter(id == ^activity.task_id)
    |> Ash.read_one(authorize?: false, tenant: activity.workspace_id)
  end

  defp in_review?(task_state_id) do
    case Citadel.Tasks.TaskState
         |> Ash.Query.filter(id == ^task_state_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, %{name: "In Review"}} -> true
      _ -> false
    end
  end

  defp get_in_progress_state do
    Citadel.Tasks.TaskState
    |> Ash.Query.filter(name == "In Progress")
    |> Ash.read_one(authorize?: false)
  end
end
