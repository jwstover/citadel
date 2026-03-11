defmodule CitadelAgent.Worker do
  @moduledoc """
  GenServer that polls Citadel for agent-eligible tasks and executes them.
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

    {:ok, %{poll_interval: poll_interval}}
  end

  @impl true
  def handle_info(:poll, state) do
    process_next_task()
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp process_next_task do
    case CitadelAgent.Client.fetch_next_task() do
      {:ok, nil} ->
        Logger.debug("No agent-eligible tasks available")

      {:ok, task} ->
        Logger.info("Picked up task #{task["human_id"]}: #{task["title"]}")
        execute_task(task)

      {:error, reason} ->
        Logger.error("Failed to fetch next task: #{inspect(reason)}")
    end
  end

  defp execute_task(task) do
    case CitadelAgent.config(:project_path) do
      nil ->
        Logger.error("No project_path configured, skipping task #{task["human_id"]}")

      project_path ->
        with {:ok, run} <- create_run(task),
             {:ok, run} <- mark_running(run) do
          run_task(task, run, project_path)
        end
    end
  end

  defp create_run(task) do
    case CitadelAgent.Client.create_run(task["id"]) do
      {:ok, run} ->
        Logger.info("Created AgentRun #{run["id"]} for task #{task["human_id"]}")
        {:ok, run}

      {:error, reason} ->
        Logger.error("Failed to create AgentRun: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp mark_running(run) do
    case CitadelAgent.Client.update_run(run["id"], %{
           "status" => "running",
           "started_at" => DateTime.utc_now() |> DateTime.to_iso8601()
         }) do
      {:ok, run} ->
        {:ok, run}

      {:error, reason} ->
        Logger.error("Failed to mark run as running: #{inspect(reason)}")
        {:error, reason}
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

      {:error, reason} ->
        CitadelAgent.Client.update_run(run["id"], %{
          "status" => "failed",
          "error_message" => inspect(reason),
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        Logger.error("Task #{task["human_id"]} failed: #{inspect(reason)}")
    end
  end
end
