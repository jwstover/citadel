defmodule CitadelWeb.Api.AgentController do
  use CitadelWeb, :controller

  alias Citadel.Tasks

  def claim_task(conn, _params) do
    require Logger
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    Logger.info("DEBUG[claim_task]: Attempting claim for tenant=#{inspect(tenant)} actor=#{inspect(actor && actor.id)}")

    case Tasks.claim_next_task(
           actor: actor,
           tenant: tenant,
           load: [:work_item, task: [:task_state, :parent_task]]
         ) do
      {:ok, agent_run} ->
        Logger.info("DEBUG[claim_task]: claim_next_task succeeded run_id=#{agent_run.id} task_id=#{agent_run.task_id}")
        Logger.info("DEBUG[claim_task]: work_item=#{inspect(agent_run.work_item)}")
        Logger.info("DEBUG[claim_task]: task.parent_task=#{inspect(agent_run.task && agent_run.task.parent_task)}")

        conn
        |> put_status(:ok)
        |> render(:claim, agent_run: agent_run)

      {:error, %Ash.Error.Invalid{} = error} ->
        Logger.info("DEBUG[claim_task]: claim_next_task returned Invalid error (no tasks): #{inspect(error)}")
        send_resp(conn, :no_content, "")
    end
  end

  def update_run(conn, %{"id" => id} = params) do
    require Logger
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

    Logger.info("DEBUG[update_run]: run_id=#{id} input_status=#{inspect(input[:status])}")

    with {:ok, agent_run} <- fetch_agent_run(id, actor, tenant),
         {:ok, updated} <- Tasks.update_agent_run(agent_run, input, actor: actor, tenant: tenant) do
      Logger.info("DEBUG[update_run]: success run_id=#{id} new_status=#{updated.status}")
      conn
      |> put_status(:ok)
      |> render(:agent_run, agent_run: updated)
    else
      :not_found ->
        Logger.error("DEBUG[update_run]: run_id=#{id} not found")
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Not Found"}})

      {:error, %Ash.Error.Invalid{} = error} ->
        Logger.error("DEBUG[update_run]: run_id=#{id} invalid error=#{inspect(error)}")
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
