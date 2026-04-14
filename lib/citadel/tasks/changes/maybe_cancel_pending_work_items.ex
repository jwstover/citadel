defmodule Citadel.Tasks.Changes.MaybeCancelPendingWorkItems do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, task ->
      if task_completed_or_cancelled?(task.task_state_id) do
        cancel_pending_work_items(task)
      end

      {:ok, task}
    end)
  end

  defp task_completed_or_cancelled?(task_state_id) do
    case Citadel.Tasks.TaskState
         |> Ash.Query.filter(id == ^task_state_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, %{is_complete: true}} -> true
      {:ok, %{name: "Cancelled"}} -> true
      _ -> false
    end
  end

  defp cancel_pending_work_items(task) do
    Citadel.Tasks.AgentWorkItem
    |> Ash.Query.filter(task_id == ^task.id and status in [:pending, :claimed])
    |> Ash.read!(authorize?: false, tenant: task.workspace_id)
    |> Enum.each(fn work_item ->
      work_item
      |> Ash.Changeset.for_update(:cancel, %{}, authorize?: false, tenant: task.workspace_id)
      |> Ash.update()
    end)
  end
end
