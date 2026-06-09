defmodule CitadelAgent.TaskRunner do
  @moduledoc """
  GenServer that wraps the execution of a single task. Owns the full lifecycle
  of one task run: fetching feedback, pushing status updates, executing via
  `Runner.execute/3`, reporting results, transitioning the task state, and
  cleaning up.

  Registers itself in the RunnerRegistry via `:via` tuple naming so the
  Registry automatically deregisters the process on termination.
  """

  use GenServer, restart: :temporary

  require Logger

  def start_link(%{task: task, run: run, project_path: project_path} = args) do
    task_id = task["id"]

    GenServer.start_link(
      __MODULE__,
      %{
        task: task,
        run: run,
        project_path: project_path,
        work_item: Map.get(args, :work_item)
      },
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
    %{task: task, run: run, project_path: project_path, work_item: work_item} = state
    run_id = run["id"]
    feedback = fetch_feedback(work_item)
    resume_session_id = fetch_resume_session_id(work_item)

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
            Logger.error("Failed to update run #{run_id}: #{inspect(reason)}")
        end

        Logger.info("Task #{task["human_id"]} completed with status: #{result.status}")
        push_stream_complete(run_id)

        %{state | active_run: nil}

      {:error, reason} ->
        CitadelAgent.Client.update_run(run_id, %{
          "status" => "failed",
          "error_message" => inspect(reason),
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        Logger.error("Task #{task["human_id"]} failed: #{inspect(reason)}")
        push_stream_complete(run_id)

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

      push_stream_complete(state.run["id"])

      %{state | active_run: nil}
  end

  defp push_stream_complete(run_id) do
    CitadelAgent.Socket.push_stream_complete(run_id)
  rescue
    e -> Logger.debug("Failed to push stream_complete: #{Exception.message(e)}")
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
        Logger.warning(
          "Failed to fetch comment #{comment_id}: #{inspect(reason)}, proceeding without feedback"
        )

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
