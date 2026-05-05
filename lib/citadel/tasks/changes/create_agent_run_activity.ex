defmodule Citadel.Tasks.Changes.CreateAgentRunActivity do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, agent_run ->
      Citadel.Tasks.TaskActivity
      |> Ash.Changeset.for_create(
        :create_for_agent_run,
        %{task_id: agent_run.task_id, agent_run_id: agent_run.id},
        actor: context.actor,
        tenant: agent_run.workspace_id
      )
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, _activity} -> {:ok, agent_run}
        {:error, error} -> {:error, error}
      end
    end)
  end
end
