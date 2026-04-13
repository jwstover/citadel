defmodule CitadelAgent.TaskRunner do
  @moduledoc """
  GenServer that wraps the execution of a single task. Owns the full lifecycle
  of one task run: pushing status updates, executing via `Runner.execute/2`,
  reporting results, transitioning the task state, and cleaning up.

  Registers itself in the RunnerRegistry via `:via` tuple naming so the
  Registry automatically deregisters the process on termination.
  """

  use GenServer, restart: :temporary

  require Logger

  def start_link(%{task: task, run: run, project_path: project_path}) do
    task_id = task["id"]

    GenServer.start_link(__MODULE__, %{task: task, run: run, project_path: project_path},
      name: {:via, Registry, {CitadelAgent.RunnerRegistry, task_id}}
    )
  end

  @impl true
  def init(state) do
    CitadelAgent.Socket.update_status("working", state.task["id"])
    send(self(), :execute)

    {:ok, Map.put(state, :active_run, state.run)}
  end

  @impl true
  def handle_info(:execute, state) do
    state = run_task(state)
    CitadelAgent.Socket.update_status("idle")
    {:stop, :normal, %{state | active_run: nil}}
  end

  @impl true
  def terminate(:normal, _state), do: :ok

  def terminate(reason, %{active_run: %{"id" => run_id}} = _state) do
    Logger.error("TaskRunner terminating with active run #{run_id}, marking as failed")

    CitadelAgent.Client.update_run(run_id, %{
      "status" => "failed",
      "error_message" => "TaskRunner process terminated: #{inspect(reason)}",
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    CitadelAgent.Socket.update_status("idle")
  end

  def terminate(_reason, _state) do
    CitadelAgent.Socket.update_status("idle")
  end

  defp run_task(state) do
    %{task: task, run: run, project_path: project_path} = state

    case CitadelAgent.Runner.execute(task, project_path) do
      {:ok, result} ->
        CitadelAgent.Client.update_run(run["id"], %{
          "status" => result.status,
          "diff" => result.diff,
          "logs" => result.logs,
          "test_output" => result.test_output,
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        Logger.info("Task #{task["human_id"]} completed with status: #{result.status}")

        if result.status == "completed" do
          transition_task_to_in_review(task)
        end

        %{state | active_run: nil}

      {:error, reason} ->
        CitadelAgent.Client.update_run(run["id"], %{
          "status" => "failed",
          "error_message" => inspect(reason),
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        Logger.error("Task #{task["human_id"]} failed: #{inspect(reason)}")
        %{state | active_run: nil}
    end
  rescue
    exception ->
      Logger.error(
        "Task #{state.task["human_id"]} crashed: #{Exception.format(:error, exception, __STACKTRACE__)}"
      )

      CitadelAgent.Client.update_run(state.run["id"], %{
        "status" => "failed",
        "error_message" => Exception.message(exception),
        "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

      %{state | active_run: nil}
  end

  defp transition_task_to_in_review(task) do
    with {:ok, states} <- CitadelAgent.Client.fetch_task_states(),
         %{"id" => state_id} <- Enum.find(states, &(&1["name"] == "In Review")) do
      case CitadelAgent.Client.update_task_state(task["id"], state_id) do
        {:ok, _task} ->
          Logger.info("Task #{task["human_id"]} transitioned to In Review")

        {:error, reason} ->
          Logger.warning(
            "Failed to transition task #{task["human_id"]} to In Review: #{inspect(reason)}"
          )
      end
    else
      nil ->
        Logger.warning("Could not find 'In Review' task state")

      {:error, reason} ->
        Logger.warning("Failed to fetch task states: #{inspect(reason)}")
    end
  end
end
