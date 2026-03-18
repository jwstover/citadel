defmodule CitadelWeb.Api.AgentController do
  use CitadelWeb, :controller

  alias Citadel.Tasks
  alias Citadel.Tasks.StallDetector

  def claim_task(conn, _params) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    case Tasks.claim_next_task(
           actor: actor,
           tenant: tenant,
           load: [:work_item, task: [:task_state, :parent_task]]
         ) do
      {:ok, agent_run} ->
        CitadelWeb.Endpoint.broadcast("tasks:agent_activity", "run_started", %{
          run_id: agent_run.id,
          task_id: agent_run.task_id,
          workspace_id: agent_run.workspace_id
        })

        conn
        |> put_status(:ok)
        |> render(:claim, agent_run: agent_run)

      {:error, %Ash.Error.Invalid{}} ->
        send_resp(conn, :no_content, "")
    end
  end

  def update_run(conn, %{"id" => id} = params) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    input =
      params
      |> Map.take([
        "status",
        "commits",
        "test_output",
        "logs",
        "error_message",
        "started_at",
        "completed_at"
      ])
      |> atomize_keys()

    with {:ok, agent_run} <- fetch_agent_run(id, actor, tenant),
         {:ok, updated} <- Tasks.update_agent_run(agent_run, input, actor: actor, tenant: tenant) do
      StallDetector.record_activity(id)

      conn
      |> put_status(:ok)
      |> render(:agent_run, agent_run: updated)
    else
      :not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Not Found"}})

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: error)
    end
  end

  def cancel_run(conn, %{"id" => id}) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    with {:ok, agent_run} <- fetch_agent_run(id, actor, tenant),
         {:ok, cancelled} <- Tasks.cancel_agent_run(agent_run, actor: actor, tenant: tenant) do
      conn
      |> put_status(:ok)
      |> render(:agent_run, agent_run: cancelled)
    else
      :not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Not Found"}})

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: error)
    end
  end

  def create_run_event(conn, %{"id" => run_id} = params) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    input =
      params
      |> Map.take(["event_type", "message", "metadata"])
      |> Map.put("agent_run_id", run_id)
      |> atomize_keys()

    case Tasks.create_agent_run_event(input, actor: actor, tenant: tenant) do
      {:ok, event} ->
        StallDetector.record_activity(run_id)

        conn
        |> put_status(:created)
        |> render(:agent_run_event, event: event)

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: error)
    end
  end

  def get_comment(conn, %{"id" => id}) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    case Tasks.get_task_activity(id, actor: actor, tenant: tenant) do
      {:ok, activity} ->
        conn
        |> put_status(:ok)
        |> render(:comment, comment: activity)

      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Not Found"}})
    end
  end

  def list_task_states(conn, _params) do
    task_states = Tasks.list_task_states!(query: [sort: [order: :asc]])

    conn
    |> put_status(:ok)
    |> render(:task_states, task_states: task_states)
  end

  def update_task(conn, %{"id" => id} = params) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    input =
      params
      |> Map.take(["task_state_id", "forge_pr"])
      |> atomize_keys()

    case Tasks.update_task(id, input,
           actor: actor,
           tenant: tenant,
           load: [:task_state, :parent_task]
         ) do
      {:ok, updated} ->
        conn
        |> put_status(:ok)
        |> render(:task, task: updated)

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
          conn
          |> put_status(:not_found)
          |> json(%{errors: %{detail: "Not Found"}})
        else
          conn
          |> put_status(:unprocessable_entity)
          |> render(:error, error: error)
        end

      {:error, _error} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Not Found"}})
    end
  end

  def create_refinement_cycle(conn, %{"run_id" => run_id} = params) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    input =
      params
      |> Map.take(["max_iterations", "evaluator_config"])
      |> Map.put("agent_run_id", run_id)
      |> atomize_keys()

    with {:ok, agent_run} <- fetch_agent_run(run_id, actor, tenant),
         :ok <- validate_run_status(agent_run),
         :ok <- validate_no_active_cycle(run_id, actor, tenant) do
      case Tasks.create_refinement_cycle(input, actor: actor, tenant: tenant) do
        {:ok, cycle} ->
          conn
          |> put_status(:created)
          |> render(:refinement_cycle, cycle: cycle)

        {:error, %Ash.Error.Invalid{} = error} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render(:error, error: error)
      end
    else
      :not_found ->
        send_not_found(conn)

      {:error, :run_not_running} ->
        send_error(conn, :unprocessable_entity, "Run is not in running status")

      {:error, :active_cycle_exists} ->
        send_error(conn, :conflict, "An active refinement cycle already exists for this run")
    end
  end

  def create_refinement_iteration(conn, %{"run_id" => run_id} = params) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    with {:ok, _agent_run} <- fetch_agent_run(run_id, actor, tenant),
         {:ok, cycle} <- fetch_active_cycle(run_id, actor, tenant) do
      input =
        params
        |> Map.take(["iteration_number", "score", "evaluation_result", "feedback", "status"])
        |> Map.put("refinement_cycle_id", cycle.id)
        |> atomize_keys()

      with {:ok, iteration} <-
             Tasks.create_refinement_iteration(input, actor: actor, tenant: tenant),
           {:ok, _cycle} <-
             Tasks.update_refinement_cycle(
               cycle,
               %{current_iteration: iteration.iteration_number},
               actor: actor,
               tenant: tenant
             ) do
        StallDetector.record_activity(run_id)

        Phoenix.PubSub.broadcast(
          Citadel.PubSub,
          "tasks:refinement:#{run_id}",
          %{
            event: "iteration_created",
            iteration: %{
              number: iteration.iteration_number,
              score: iteration.score,
              feedback: iteration.feedback,
              status: iteration.status
            }
          }
        )

        conn
        |> put_status(:created)
        |> render(:refinement_iteration, iteration: iteration)
      else
        {:error, %Ash.Error.Invalid{} = error} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render(:error, error: error)
      end
    else
      :not_found ->
        send_not_found(conn)

      {:error, :no_active_cycle} ->
        send_error(conn, :unprocessable_entity, "No active refinement cycle for this run")
    end
  end

  def update_refinement_cycle(conn, %{"run_id" => run_id} = params) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    with {:ok, _agent_run} <- fetch_agent_run(run_id, actor, tenant),
         {:ok, cycle} <- fetch_active_cycle(run_id, actor, tenant) do
      result =
        case params["status"] do
          "passed" ->
            final_score = params["final_score"] || 0.0

            Tasks.complete_refinement_cycle(cycle, %{final_score: final_score},
              actor: actor,
              tenant: tenant
            )

          status when status in ["failed_max_iterations", "error"] ->
            Tasks.fail_refinement_cycle(cycle, %{reason: String.to_existing_atom(status)},
              actor: actor,
              tenant: tenant
            )

          _ ->
            {:error, :invalid_status}
        end

      case result do
        {:ok, updated_cycle} ->
          StallDetector.record_activity(run_id)

          Phoenix.PubSub.broadcast(
            Citadel.PubSub,
            "tasks:refinement:#{run_id}",
            %{
              event: "cycle_completed",
              status: updated_cycle.status,
              final_score: updated_cycle.final_score
            }
          )

          conn
          |> put_status(:ok)
          |> render(:refinement_cycle, cycle: updated_cycle)

        {:error, :invalid_status} ->
          send_error(
            conn,
            :unprocessable_entity,
            "Status must be passed, failed_max_iterations, or error"
          )

        {:error, %Ash.Error.Invalid{} = error} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render(:error, error: error)
      end
    else
      :not_found ->
        send_not_found(conn)

      {:error, :no_active_cycle} ->
        send_error(conn, :unprocessable_entity, "No active refinement cycle for this run")
    end
  end

  defp validate_run_status(agent_run) do
    if agent_run.status == :running, do: :ok, else: {:error, :run_not_running}
  end

  defp validate_no_active_cycle(run_id, actor, tenant) do
    case Tasks.get_refinement_cycle_by_agent_run(run_id, actor: actor, tenant: tenant) do
      {:ok, [%{status: :running} | _]} -> {:error, :active_cycle_exists}
      _ -> :ok
    end
  end

  defp fetch_active_cycle(run_id, actor, tenant) do
    case Tasks.get_refinement_cycle_by_agent_run(run_id, actor: actor, tenant: tenant) do
      {:ok, [%{status: :running} = cycle | _]} -> {:ok, cycle}
      _ -> {:error, :no_active_cycle}
    end
  end

  defp send_not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "Not Found"}})
  end

  defp send_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{errors: %{detail: message}})
  end

  defp fetch_agent_run(id, actor, tenant) do
    case Tasks.get_agent_run(id, actor: actor, tenant: tenant) do
      {:ok, agent_run} -> {:ok, agent_run}
      {:error, _} -> :not_found
    end
  end

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
