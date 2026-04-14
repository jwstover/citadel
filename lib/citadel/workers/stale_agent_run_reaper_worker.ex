defmodule Citadel.Workers.StaleAgentRunReaperWorker do
  @moduledoc """
  Oban cron worker that detects and fails orphaned AgentRuns.

  An AgentRun can become stuck in :running or :pending status when the
  runner loses the HTTP response during claim, crashes during execution,
  or fails to report back. These stuck runs permanently block the task
  from future agent work because both `ClaimNextTask` and
  `MaybeEnqueueAgentWork` skip tasks with active runs.

  Uses a two-tier detection strategy:
  1. **Presence check** — if a connected agent is actively working on the
     run's task, the run is legitimate regardless of how long it's been
     running. This avoids reaping long-running but healthy executions.
  2. **Staleness threshold** — runs without a connected agent are failed
     after 30 minutes (:running) or 60 minutes (:pending) of no updates.

  Runs every 5 minutes.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Logger

  import Ecto.Query

  alias CitadelWeb.AgentPresence

  @running_threshold_minutes 30
  @pending_threshold_minutes 60

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    running_cutoff = DateTime.add(DateTime.utc_now(), -@running_threshold_minutes, :minute)
    pending_cutoff = DateTime.add(DateTime.utc_now(), -@pending_threshold_minutes, :minute)

    stale_runs = find_stale_runs(running_cutoff, pending_cutoff)

    if stale_runs == [] do
      Logger.debug("StaleAgentRunReaper: no stale runs found")
    else
      Logger.info("StaleAgentRunReaper: found #{length(stale_runs)} stale candidate(s)")

      Enum.each(stale_runs, &maybe_fail_stale_run/1)
    end

    :ok
  end

  defp find_stale_runs(running_cutoff, pending_cutoff) do
    from(ar in Citadel.Tasks.AgentRun,
      where:
        (ar.status == :running and ar.updated_at < ^running_cutoff) or
          (ar.status == :pending and ar.updated_at < ^pending_cutoff),
      select: %{id: ar.id, workspace_id: ar.workspace_id, task_id: ar.task_id, status: ar.status}
    )
    |> Citadel.Repo.all()
  end

  defp maybe_fail_stale_run(%{task_id: task_id, workspace_id: workspace_id} = run) do
    if agent_working_on_task?(workspace_id, task_id) do
      Logger.debug(
        "StaleAgentRunReaper: skipping run #{run.id}, agent still connected and working"
      )
    else
      cancel_stale_run(run)
    end
  end

  defp agent_working_on_task?(workspace_id, task_id) do
    topic = "agents:#{workspace_id}"
    task_id_string = to_string(task_id)

    AgentPresence.list(topic)
    |> Enum.any?(fn {_name, %{metas: metas}} ->
      Enum.any?(metas, fn meta ->
        meta[:status] == "working" and to_string(meta[:current_task_id]) == task_id_string
      end)
    end)
  end

  defp cancel_stale_run(%{id: id, workspace_id: workspace_id, status: status}) do
    require Ash.Query

    case Citadel.Tasks.AgentRun
         |> Ash.Query.filter(id == ^id)
         |> Ash.read_one(authorize?: false, tenant: workspace_id) do
      {:ok, %{status: current_status} = run} when current_status in [:running, :pending] ->
        reason = "Reaped: #{status} run had no connected agent"

        Citadel.Tasks.cancel_agent_run!(run, %{reason: reason},
          authorize?: false,
          tenant: workspace_id
        )

        Logger.info("StaleAgentRunReaper: cancelled orphaned #{status} run #{id}")

      {:ok, _run} ->
        Logger.debug("StaleAgentRunReaper: run #{id} already resolved, skipping")

      {:error, reason} ->
        Logger.warning("StaleAgentRunReaper: failed to load run #{id}: #{inspect(reason)}")
    end
  end
end
