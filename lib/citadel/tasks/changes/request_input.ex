defmodule Citadel.Tasks.Changes.RequestInput do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query
  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, activity ->
      request_input(activity)
      {:ok, activity}
    end)
  end

  defp request_input(%{agent_run_id: nil}), do: :ok

  defp request_input(activity) do
    with {:ok, agent_run} <- get_agent_run(activity) do
      agent_run
      |> Ash.Changeset.for_update(
        :request_input,
        %{},
        authorize?: false,
        tenant: activity.workspace_id
      )
      |> Ash.update()
      |> case do
        {:ok, _run} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to transition AgentRun #{activity.agent_run_id} to input_requested: #{inspect(reason)}"
          )

          :ok
      end
    end
  rescue
    e ->
      Logger.warning(
        "Error requesting input for AgentRun #{activity.agent_run_id}: #{inspect(e)}"
      )

      :ok
  end

  defp get_agent_run(activity) do
    Citadel.Tasks.AgentRun
    |> Ash.Query.filter(id == ^activity.agent_run_id)
    |> Ash.read_one(authorize?: false, tenant: activity.workspace_id)
  end
end
