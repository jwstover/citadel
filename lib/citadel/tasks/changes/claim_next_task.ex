defmodule Citadel.Tasks.Changes.ClaimNextTask do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query
  import Ecto.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      workspace_id = context.tenant

      case claim_next_work_item(workspace_id) do
        nil ->
          Ash.Changeset.add_error(changeset,
            field: :task_id,
            message: "no tasks available"
          )

        {task_id, work_item_id} ->
          apply_claim(changeset, task_id, work_item_id, workspace_id)
      end
    end)
  end

  defp apply_claim(changeset, task_id, work_item_id, workspace_id) do
    changeset
    |> Ash.Changeset.force_change_attribute(:task_id, task_id)
    |> Ash.Changeset.force_change_attribute(:workspace_id, workspace_id)
    |> Ash.Changeset.force_change_attribute(:status, :running)
    |> Ash.Changeset.force_change_attribute(:started_at, DateTime.utc_now())
    |> Ash.Changeset.after_action(fn _changeset, agent_run ->
      claim_work_item(work_item_id, agent_run.id, workspace_id)
      transition_task_and_ancestors_to_in_progress(task_id, workspace_id)
      {:ok, agent_run}
    end)
  end

  defp claim_next_work_item(workspace_id) do
    active_runs_subquery =
      from ar in Citadel.Tasks.AgentRun,
        where: ar.task_id == parent_as(:task).id,
        where: ar.status in [:pending, :running],
        select: 1

    incomplete_deps_subquery =
      from td in "task_dependencies",
        join: dep in Citadel.Tasks.Task,
        on: dep.id == td.depends_on_task_id,
        join: dep_ts in Citadel.Tasks.TaskState,
        on: dep_ts.id == dep.task_state_id,
        where: td.task_id == parent_as(:task).id,
        where: dep_ts.is_complete != true,
        select: 1

    priority_order =
      dynamic(
        [work_item: _wi, task: t],
        fragment(
          "CASE ? WHEN 'urgent' THEN 4 WHEN 'high' THEN 3 WHEN 'medium' THEN 2 WHEN 'low' THEN 1 ELSE 0 END",
          t.priority
        )
      )

    query =
      from wi in Citadel.Tasks.AgentWorkItem,
        as: :work_item,
        join: t in Citadel.Tasks.Task,
        as: :task,
        on: t.id == wi.task_id,
        join: ts in Citadel.Tasks.TaskState,
        on: ts.id == t.task_state_id,
        where: wi.workspace_id == ^workspace_id,
        where: wi.status == :pending,
        where: ts.is_complete != true,
        where: ts.name != "In Review",
        where: ts.name != "Backlog",
        where: not exists(active_runs_subquery),
        where: not exists(incomplete_deps_subquery),
        order_by: ^[desc: priority_order, asc: dynamic([work_item: wi], wi.inserted_at)],
        limit: 1,
        lock: "FOR UPDATE SKIP LOCKED",
        select: {t.id, wi.id}

    Citadel.Repo.one(query)
  end

  defp claim_work_item(work_item_id, agent_run_id, workspace_id) do
    Citadel.Tasks.AgentWorkItem
    |> Ash.Query.filter(id == ^work_item_id)
    |> Ash.read_one!(authorize?: false, tenant: workspace_id)
    |> Ash.Changeset.for_update(:claim, %{agent_run_id: agent_run_id},
      authorize?: false,
      tenant: workspace_id
    )
    |> Ash.update!()
  end

  defp transition_task_and_ancestors_to_in_progress(task_id, workspace_id) do
    case get_in_progress_state() do
      {:ok, in_progress_state} ->
        transition_chain(task_id, in_progress_state.id, workspace_id)

      _ ->
        :ok
    end
  end

  defp transition_chain(nil, _in_progress_id, _workspace_id), do: :ok

  defp transition_chain(task_id, in_progress_id, workspace_id) do
    task =
      Citadel.Tasks.Task
      |> Ash.Query.filter(id == ^task_id)
      |> Ash.read_one!(authorize?: false, tenant: workspace_id)

    if task.task_state_id != in_progress_id do
      task
      |> Ash.Changeset.for_update(:update, %{task_state_id: in_progress_id},
        authorize?: false,
        tenant: workspace_id
      )
      |> Ash.update!()
    end

    transition_chain(task.parent_task_id, in_progress_id, workspace_id)
  end

  defp get_in_progress_state do
    Citadel.Tasks.TaskState
    |> Ash.Query.filter(name == "In Progress")
    |> Ash.read_one(authorize?: false)
  end
end
