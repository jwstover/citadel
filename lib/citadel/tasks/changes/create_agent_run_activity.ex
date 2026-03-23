defmodule Citadel.Tasks.Changes.CreateAgentRunActivity do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, agent_run ->
      Citadel.Tasks.TaskActivity
      |> Ash.Changeset.for_create(
        :create_agent_run_activity,
        %{task_id: agent_run.task_id, agent_run_id: agent_run.id},
        tenant: agent_run.workspace_id
      )
      |> Ash.create!(authorize?: false)

      {:ok, agent_run}
    end)
  end
end
