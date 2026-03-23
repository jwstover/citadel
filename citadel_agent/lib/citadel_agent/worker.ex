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

      {:ok, %{"task" => task, "agent_run" => run} = claim} ->
        Logger.info("Claimed task #{task["human_id"]}: #{task["title"]}")
        work_item = claim["work_item"]
        feedback = fetch_feedback(work_item)
        resume_session_id = fetch_resume_session_id(work_item)
        execute_task(task, run, feedback, resume_session_id, state)

      {:error, reason} ->
        Logger.error("Failed to claim task: #{inspect(reason)}")
        state
    end
  end

  defp execute_task(task, run, feedback, resume_session_id, state) do
    case CitadelAgent.config(:project_path) do
      nil ->
        Logger.error("No project_path configured, skipping task #{task["human_id"]}")
        state

      project_path ->
        state = %{state | active_run: run}
        CitadelAgent.Socket.update_status("working", task["id"])
        run_task(task, run, feedback, resume_session_id, project_path)
        CitadelAgent.Socket.update_status("idle")
        %{state | active_run: nil}
    end
  end

  defp run_task(task, run, feedback, resume_session_id, project_path) do
    run_id = run["id"]

    case CitadelAgent.Runner.execute(task, project_path,
           run_id: run_id,
           feedback: feedback,
           resume_session_id: resume_session_id
         ) do
      {:ok, result} ->
        case CitadelAgent.Client.update_run(run_id, %{
               "status" => result.status,
               "commits" => result.commits,
               "logs" => result.logs,
               "test_output" => result.test_output,
               "session_id" => result.session_id,
               "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
             }) do
          {:ok, %{"status" => "completed"}} ->
            transition_task_to_in_review(task)

          {:ok, _run} ->
            Logger.info(
              "Task #{task["human_id"]} run ended with non-completed status, skipping In Review"
            )

          {:error, reason} ->
            Logger.error(
              "Failed to update run #{run_id}: #{inspect(reason)}"
            )
        end

        Logger.info("Task #{task["human_id"]} completed with status: #{result.status}")
        push_stream_complete(run_id)

      {:error, reason} ->
        CitadelAgent.Client.update_run(run_id, %{
          "status" => "failed",
          "error_message" => inspect(reason),
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        Logger.error("Task #{task["human_id"]} failed: #{inspect(reason)}")
        push_stream_complete(run_id)
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

      push_stream_complete(run["id"])
  end

  defp push_stream_complete(run_id) do
    try do
      CitadelAgent.Socket.push_stream_complete(run_id)
    rescue
      e -> Logger.debug("Failed to push stream_complete: #{Exception.message(e)}")
    end
  end

  defp fetch_feedback(%{"type" => "changes_requested", "comment_id" => comment_id})
       when is_binary(comment_id) do
    fetch_comment_body(comment_id)
  end

  defp fetch_feedback(%{"type" => "question_answered", "comment_id" => comment_id})
       when is_binary(comment_id) do
    fetch_comment_body(comment_id)
  end

  defp fetch_feedback(_work_item), do: nil

  defp fetch_comment_body(comment_id) do
    case CitadelAgent.Client.fetch_comment(comment_id) do
      {:ok, %{"body" => body}} when is_binary(body) ->
        Logger.info("Fetched feedback comment #{comment_id}")
        body

      {:ok, _} ->
        Logger.warning("Comment #{comment_id} had no body, proceeding without feedback")
        nil

      {:error, reason} ->
        Logger.warning("Failed to fetch comment #{comment_id}: #{inspect(reason)}, proceeding without feedback")
        nil
    end
  end

  defp fetch_resume_session_id(%{"type" => "question_answered", "session_id" => session_id})
       when is_binary(session_id) do
    session_id
  end

  defp fetch_resume_session_id(_work_item), do: nil

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
