defmodule Citadel.Tasks.Changes.ClaimNextTask do
  @moduledoc false
  use Ash.Resource.Change

  import Ecto.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      workspace_id = context.tenant

      case find_eligible_task(workspace_id) do
        nil ->
          Ash.Changeset.add_error(changeset,
            field: :task_id,
            message: "no tasks available"
          )

        task_id ->
          changeset
          |> Ash.Changeset.force_change_attribute(:task_id, task_id)
          |> Ash.Changeset.force_change_attribute(:workspace_id, workspace_id)
          |> Ash.Changeset.force_change_attribute(:status, :running)
          |> Ash.Changeset.force_change_attribute(:started_at, DateTime.utc_now())
      end
    end)
  end

  defp find_eligible_task(workspace_id) do
    active_runs_subquery =
      from ar in "agent_runs",
        where: ar.task_id == parent_as(:task).id,
        where: ar.status in ["pending", "running"],
        select: 1

    incomplete_deps_subquery =
      from td in "task_dependencies",
        join: dep in "tasks", on: dep.id == td.depends_on_task_id,
        join: dep_ts in "task_states", on: dep_ts.id == dep.task_state_id,
        where: td.task_id == parent_as(:task).id,
        where: dep_ts.is_complete != true,
        select: 1

    priority_order =
      dynamic(
        [task: t],
        fragment(
          "CASE ? WHEN 'urgent' THEN 4 WHEN 'high' THEN 3 WHEN 'medium' THEN 2 WHEN 'low' THEN 1 ELSE 0 END",
          t.priority
        )
      )

    query =
      from t in Citadel.Tasks.Task,
        as: :task,
        join: ts in Citadel.Tasks.TaskState,
        on: ts.id == t.task_state_id,
        where: t.workspace_id == ^workspace_id,
        where: t.agent_eligible == true,
        where: ts.is_complete != true,
        where: ts.name != "In Review",
        where: not exists(active_runs_subquery),
        where: not exists(incomplete_deps_subquery),
        order_by: ^[desc: priority_order, asc: dynamic([task: t], t.inserted_at)],
        limit: 1,
        lock: "FOR UPDATE OF t0 SKIP LOCKED",
        select: t.id

    Citadel.Repo.one(query)
  end
end
