defmodule Citadel.Workers.StaleAgentRunReaperWorker do
  @moduledoc """
  Oban cron worker that detects and fails orphaned AgentRuns.

  An AgentRun can become stuck in :running or :pending status when the
  runner loses the HTTP response during claim, crashes during execution,
  or fails to report back. These stuck runs permanently block the task
  from future agent work because both `ClaimNextTask` and
  `MaybeEnqueueAgentWork` skip tasks with active runs.

  Runs every 5 minutes to find and fail runs that haven't been updated
  within the configured thresholds.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Logger

  import Ecto.Query

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
      Logger.info("StaleAgentRunReaper: found #{length(stale_runs)} stale run(s)")

      Enum.each(stale_runs, &fail_stale_run/1)
    end

    :ok
  end

  defp find_stale_runs(running_cutoff, pending_cutoff) do
    from(ar in "agent_runs",
      where:
        (ar.status == "running" and ar.updated_at < ^running_cutoff) or
          (ar.status == "pending" and ar.updated_at < ^pending_cutoff),
      select: %{id: ar.id, workspace_id: ar.workspace_id, status: ar.status}
    )
    |> Citadel.Repo.all()
  end

  defp fail_stale_run(%{id: id, workspace_id: workspace_id, status: status}) do
    require Ash.Query

    case Citadel.Tasks.AgentRun
         |> Ash.Query.filter(id == ^id)
         |> Ash.read_one(authorize?: false, tenant: workspace_id) do
      {:ok, %{status: current_status} = run} when current_status in [:running, :pending] ->
        Citadel.Tasks.update_agent_run!(
          run,
          %{
            status: :failed,
            error_message: "Reaped: #{status} run stale with no recent activity",
            completed_at: DateTime.utc_now()
          },
          authorize?: false,
          tenant: workspace_id
        )

        Logger.info("StaleAgentRunReaper: failed stale #{status} run #{id}")

      {:ok, _run} ->
        Logger.debug("StaleAgentRunReaper: run #{id} already resolved, skipping")

      {:error, reason} ->
        Logger.warning("StaleAgentRunReaper: failed to load run #{id}: #{inspect(reason)}")
    end
  end
end
