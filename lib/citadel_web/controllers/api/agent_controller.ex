defmodule CitadelWeb.Api.AgentController do
  use CitadelWeb, :controller

  alias Citadel.Tasks

  def next_task(conn, _params) do
    require Ash.Query

    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    case Citadel.Tasks.Task
         |> Ash.Query.filter(agent_eligible == true)
         |> Ash.Query.filter(not exists(agent_runs, status in [:pending, :running]))
         |> Ash.Query.filter(task_state.is_complete != true and task_state.name != "In Review")
         |> Ash.Query.filter(not exists(dependencies, task_state.is_complete != true))
         |> Ash.Query.sort(priority: :desc, inserted_at: :asc)
         |> Ash.Query.limit(1)
         |> Ash.Query.load([:task_state, :parent_task])
         |> Ash.read(actor: actor, tenant: tenant) do
      {:ok, [task]} ->
        conn
        |> put_status(:ok)
        |> render(:task, task: task)

      {:ok, []} ->
        send_resp(conn, :no_content, "")
    end
  end

  def create_run(conn, %{"task_id" => task_id} = params) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    input =
      params
      |> Map.take(["status"])
      |> Map.put("task_id", task_id)
      |> atomize_keys()

    case Tasks.create_agent_run(input, actor: actor, tenant: tenant) do
      {:ok, agent_run} ->
        conn
        |> put_status(:created)
        |> render(:agent_run, agent_run: agent_run)

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: error)
    end
  end

  def update_run(conn, %{"id" => id} = params) do
    tenant = Ash.PlugHelpers.get_tenant(conn)
    actor = conn.assigns.current_user

    input =
      params
      |> Map.take([
        "status",
        "diff",
        "test_output",
        "logs",
        "error_message",
        "started_at",
        "completed_at"
      ])
      |> atomize_keys()

    with {:ok, agent_run} <- fetch_agent_run(id, actor, tenant),
         {:ok, updated} <- Tasks.update_agent_run(agent_run, input, actor: actor, tenant: tenant) do
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
        conn
        |> put_status(:created)
        |> render(:agent_run_event, event: event)

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: error)
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
      |> Map.take(["task_state_id"])
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
