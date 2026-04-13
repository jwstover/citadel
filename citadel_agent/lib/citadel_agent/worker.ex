defmodule CitadelAgent.Worker do
  @moduledoc """
  GenServer that polls Citadel for agent-eligible tasks and spawns a
  `CitadelAgent.TaskRunner` process for each claimed task.
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
    if CitadelAgent.Runners.has_active_runner?() do
      Logger.debug("Runner already active, skipping poll")
    else
      claim_and_spawn()
    end
  end

  defp claim_and_spawn do
    case CitadelAgent.Client.claim_task() do
      {:ok, nil} ->
        Logger.debug("No agent-eligible tasks available")
        CitadelAgent.Socket.update_status("idle")

      {:ok, %{"task" => task, "agent_run" => run}} ->
        Logger.info("Claimed task #{task["human_id"]}: #{task["title"]}")
        spawn_runner(task, run)

      {:error, reason} ->
        Logger.error("Failed to claim task: #{inspect(reason)}")
    end
  end

  defp spawn_runner(task, run) do
    case CitadelAgent.config(:project_path) do
      nil ->
        Logger.error("No project_path configured, skipping task #{task["human_id"]}")

      project_path ->
        child_spec = {
          CitadelAgent.TaskRunner,
          %{task: task, run: run, project_path: project_path}
        }

        case DynamicSupervisor.start_child(CitadelAgent.RunnerSupervisor, child_spec) do
          {:ok, pid} ->
            Logger.info("Started TaskRunner #{inspect(pid)} for task #{task["human_id"]}")

          {:error, reason} ->
            Logger.error("Failed to start TaskRunner for task #{task["human_id"]}: #{inspect(reason)}")
        end
    end
  end
end
