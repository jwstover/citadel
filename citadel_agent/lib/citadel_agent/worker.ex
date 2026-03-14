defmodule CitadelAgent.Worker do
  @moduledoc """
  GenServer that polls Citadel for agent-eligible tasks and executes them.

  Tracks the active AgentRun in state so that `terminate/2` can mark it as
  failed if the process crashes unexpectedly.
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    poll_interval = CitadelAgent.config(:poll_interval) || 10_000
    send(self(), :poll)

    Logger.info("CitadelAgent.Worker started, polling every #{poll_interval}ms")

    {:ok, %{poll_interval: poll_interval, active_run: nil}}
  end

  @impl true
  def handle_info(:poll, state) do
    state = process_next_task(state)
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %{active_run: %{"id" => run_id}}) do
    Logger.error("Worker terminating with active run #{run_id}, marking as failed")

    CitadelAgent.Client.update_run(run_id, %{
      "status" => "failed",
      "error_message" => "Worker process terminated: #{inspect(reason)}",
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  def terminate(_reason, _state), do: :ok

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp process_next_task(state) do
    case CitadelAgent.Client.claim_task() do
      {:ok, nil} ->
        Logger.debug("No agent-eligible tasks available")
        CitadelAgent.Socket.update_status("idle")
        state

      {:ok, %{"task" => task, "agent_run" => run}} ->
        Logger.info("Claimed task #{task["human_id"]}: #{task["title"]}")
        execute_task(task, run, state)

      {:error, reason} ->
        Logger.error("Failed to claim task: #{inspect(reason)}")
        state
    end
  end

  defp execute_task(task, run, state) do
    case CitadelAgent.config(:project_path) do
      nil ->
        Logger.error("No project_path configured, skipping task #{task["human_id"]}")
        state

      project_path ->
        state = %{state | active_run: run}
        CitadelAgent.Socket.update_status("working", task["id"])
        run_task(task, run, project_path)
        CitadelAgent.Socket.update_status("idle")
        %{state | active_run: nil}
    end
  end

  defp run_task(task, run, project_path) do
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

      {:error, reason} ->
        CitadelAgent.Client.update_run(run["id"], %{
          "status" => "failed",
          "error_message" => inspect(reason),
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        Logger.error("Task #{task["human_id"]} failed: #{inspect(reason)}")
    end
  rescue
    exception ->
      Logger.error(
        "Task #{task["human_id"]} crashed: #{Exception.format(:error, exception, __STACKTRACE__)}"
      )

      CitadelAgent.Client.update_run(run["id"], %{
        "status" => "failed",
        "error_message" => Exception.message(exception),
        "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })
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
