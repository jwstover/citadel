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
    require Logger

    work_item_action =
      case agent_run.status do
        :completed -> :complete
        :failed -> :complete
        :cancelled -> :cancel
        _ -> nil
      end

    Logger.info("DEBUG[sync_work_item]: run_id=#{agent_run.id} status=#{agent_run.status} work_item_action=#{inspect(work_item_action)} workspace_id=#{agent_run.workspace_id}")

    if work_item_action do
      work_items =
        Citadel.Tasks.AgentWorkItem
        |> Ash.Query.filter(agent_run_id == ^agent_run.id and status == :claimed)
        |> Ash.read!(authorize?: false, tenant: agent_run.workspace_id)

      Logger.info("DEBUG[sync_work_item]: found #{length(work_items)} claimed work item(s) for run_id=#{agent_run.id}")

      Enum.each(work_items, fn work_item ->
        Logger.info("DEBUG[sync_work_item]: applying :#{work_item_action} to work_item_id=#{work_item.id}")

        result =
          work_item
          |> Ash.Changeset.for_update(work_item_action, %{},
            authorize?: false,
            tenant: agent_run.workspace_id
          )
          |> Ash.update()

        Logger.info("DEBUG[sync_work_item]: work_item update result=#{inspect(result)}")
      end)
    end
  end
end
