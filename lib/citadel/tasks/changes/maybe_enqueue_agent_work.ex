defmodule Citadel.Tasks.Changes.MaybeEnqueueAgentWork do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, task ->
      maybe_create_work_item(task)
      maybe_enqueue_unblocked_dependents(task)
      {:ok, task}
    end)
  end

  defp maybe_create_work_item(task) do
    if should_enqueue?(task) do
      create_work_item(task)
    end
  end

  defp should_enqueue?(task) do
    require Logger

    eligible = task.agent_eligible == true
    workable = workable_state?(task.task_state_id)
    blocked = blocked?(task)
    active_run = active_run_exists?(task.id, task.workspace_id)
    active_work_item = active_work_item_exists?(task.id, task.workspace_id)

    result = eligible && workable && !blocked && !active_run && !active_work_item

    unless result do
      Logger.warning(
        "MaybeEnqueueAgentWork: skipping task #{task.id} — " <>
          "eligible=#{eligible}, workable=#{workable}, blocked=#{blocked}, " <>
          "active_run=#{active_run}, active_work_item=#{active_work_item}"
      )
    end

    result
  end

  defp blocked?(task) do
    Citadel.Tasks.TaskDependency
    |> Ash.Query.filter(task_id == ^task.id)
    |> Ash.read!(authorize?: false)
    |> Enum.any?(fn dep ->
      dep_task =
        Citadel.Tasks.Task
        |> Ash.Query.filter(id == ^dep.depends_on_task_id)
        |> Ash.read_one!(authorize?: false, tenant: task.workspace_id)

      !complete_state?(dep_task.task_state_id)
    end)
  end

  defp maybe_enqueue_unblocked_dependents(task) do
    if complete_state?(task.task_state_id) do
      enqueue_eligible_dependents(task)
    end
  end

  defp enqueue_eligible_dependents(task) do
    Citadel.Tasks.TaskDependency
    |> Ash.Query.filter(depends_on_task_id == ^task.id)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn dep ->
      dependent_task =
        Citadel.Tasks.Task
        |> Ash.Query.filter(id == ^dep.task_id)
        |> Ash.read_one!(
          authorize?: false,
          tenant: task.workspace_id,
          load: [dependencies: [task_state: [:is_complete]]]
        )

      if dependent_task do
        maybe_create_work_item(dependent_task)
      end
    end)
  end

  defp complete_state?(task_state_id) do
    case Citadel.Tasks.TaskState
         |> Ash.Query.filter(id == ^task_state_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, %{is_complete: true}} -> true
      _ -> false
    end
  end

  defp workable_state?(task_state_id) do
    case Citadel.Tasks.TaskState
         |> Ash.Query.filter(id == ^task_state_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, %{is_complete: true}} -> false
      {:ok, %{name: "In Review"}} -> false
      {:ok, %{name: "Backlog"}} -> false
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
