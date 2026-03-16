defmodule Citadel.Tasks.Changes.MaybeEnqueueAgentWork do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, task ->
      maybe_create_work_item(task)
      {:ok, task}
    end)
  end

  defp maybe_create_work_item(task) do
    if should_enqueue?(task) do
      create_work_item(task)
    end
  end

  defp should_enqueue?(task) do
    task.agent_eligible == true &&
      workable_state?(task.task_state_id) &&
      !active_run_exists?(task.id, task.workspace_id) &&
      !active_work_item_exists?(task.id, task.workspace_id)
  end

  defp workable_state?(task_state_id) do
    case Citadel.Tasks.TaskState
         |> Ash.Query.filter(id == ^task_state_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, %{is_complete: true}} -> false
      {:ok, %{name: "In Review"}} -> false
      {:ok, %{}} -> true
      _ -> false
    end
  end

  defp active_run_exists?(task_id, workspace_id) do
    Citadel.Tasks.AgentRun
    |> Ash.Query.filter(task_id == ^task_id and status in [:pending, :running])
    |> Ash.exists?(authorize?: false, tenant: workspace_id)
  end

  defp active_work_item_exists?(task_id, workspace_id) do
    Citadel.Tasks.AgentWorkItem
    |> Ash.Query.filter(task_id == ^task_id and status in [:pending, :claimed])
    |> Ash.exists?(authorize?: false, tenant: workspace_id)
  end

  defp create_work_item(task) do
    Citadel.Tasks.AgentWorkItem
    |> Ash.Changeset.for_create(:create, %{type: :new_task, task_id: task.id},
      authorize?: false,
      tenant: task.workspace_id
    )
    |> Ash.create()
    |> case do
      {:ok, _work_item} -> :ok
      {:error, _} -> :ok
    end
  end
end
