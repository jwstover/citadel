defmodule Citadel.Tasks.Changes.SyncWorkItemStatus do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, agent_run ->
      update_work_item_for_run(agent_run)
      {:ok, agent_run}
    end)
  end

  defp update_work_item_for_run(agent_run) do
    work_item_action =
      case agent_run.status do
        :completed -> :complete
        :failed -> :complete
        :cancelled -> :cancel
        _ -> nil
      end

    if work_item_action do
      Citadel.Tasks.AgentWorkItem
      |> Ash.Query.filter(agent_run_id == ^agent_run.id and status == :claimed)
      |> Ash.read!(authorize?: false, tenant: agent_run.workspace_id)
      |> Enum.each(fn work_item ->
        work_item
        |> Ash.Changeset.for_update(work_item_action, %{},
          authorize?: false,
          tenant: agent_run.workspace_id
        )
        |> Ash.update()
      end)
    end
  end
end
