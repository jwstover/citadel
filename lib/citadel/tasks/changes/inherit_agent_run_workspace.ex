defmodule Citadel.Tasks.Changes.InheritAgentRunWorkspace do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, %{tenant: tenant}) do
    case Ash.Changeset.get_attribute(changeset, :agent_run_id) do
      nil ->
        changeset

      agent_run_id ->
        set_workspace_from_agent_run(changeset, agent_run_id, tenant)
    end
  end

  defp set_workspace_from_agent_run(changeset, agent_run_id, tenant) do
    case Citadel.Tasks.AgentRun
         |> Ash.Query.filter(id == ^agent_run_id)
         |> Ash.read_one(authorize?: false, tenant: tenant) do
      {:ok, %{workspace_id: workspace_id}} ->
        Ash.Changeset.force_change_attribute(changeset, :workspace_id, workspace_id)

      {:ok, nil} ->
        Ash.Changeset.add_error(changeset,
          field: :agent_run_id,
          message: "agent run not found"
        )

      {:error, _} ->
        Ash.Changeset.add_error(changeset,
          field: :agent_run_id,
          message: "agent run not found"
        )
    end
  end
end
