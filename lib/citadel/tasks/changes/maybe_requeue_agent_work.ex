defmodule Citadel.Tasks.Changes.MaybeRequeueAgentWork do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query

  @max_consecutive_failures 3

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, agent_run ->
      if agent_run.status in [:failed, :cancelled] do
        maybe_requeue(agent_run)
      end

      {:ok, agent_run}
    end)
  end

  defp maybe_requeue(agent_run) do
    task = load_task(agent_run.task_id, agent_run.workspace_id)

    if task && should_requeue?(task, agent_run) do
      create_work_item(task)
    end
  end

  defp load_task(task_id, workspace_id) do
    Citadel.Tasks.Task
    |> Ash.Query.filter(id == ^task_id)
    |> Ash.read_one!(authorize?: false, tenant: workspace_id)
  end

  defp should_requeue?(task, agent_run) do
    require Logger

    eligible = task.agent_eligible == true
    workable = workable_state?(task.task_state_id)
    blocked = blocked?(task)
    active_run = active_run_exists?(task.id, task.workspace_id)
    active_work_item = active_work_item_exists?(task.id, task.workspace_id)

    base_eligible = eligible && workable && !blocked && !active_run && !active_work_item

    if base_eligible && agent_run.status == :failed do
      count = consecutive_failure_count(task.id, task.workspace_id)

      if count >= @max_consecutive_failures do
        Logger.warning(
          "MaybeRequeueAgentWork: disabling agent_eligible for task #{task.id} — " <>
            "#{count} consecutive failures"
        )

        disable_agent_eligible(task)
        false
      else
        true
      end
    else
      unless base_eligible do
        Logger.warning(
          "MaybeRequeueAgentWork: skipping task #{task.id} — " <>
            "eligible=#{eligible}, workable=#{workable}, blocked=#{blocked}, " <>
            "active_run=#{active_run}, active_work_item=#{active_work_item}"
        )
      end

      base_eligible
    end
  end

  defp consecutive_failure_count(task_id, workspace_id) do
    Citadel.Tasks.AgentRun
    |> Ash.Query.filter(task_id == ^task_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false, tenant: workspace_id)
    |> Enum.reduce_while(0, fn run, count ->
      if run.status == :failed do
        {:cont, count + 1}
      else
        {:halt, count}
      end
    end)
  end

  defp disable_agent_eligible(task) do
    task
    |> Ash.Changeset.for_update(:update, %{agent_eligible: false},
      authorize?: false,
      tenant: task.workspace_id
    )
    |> Ash.update()
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
