defmodule CitadelWeb.AgentChannel do
  @moduledoc false

  use Phoenix.Channel

  require Logger

  alias Citadel.Accounts
  alias Citadel.Tasks
  alias CitadelWeb.AgentPresence

  @impl true
  def join("agents:" <> _, %{"agent_name" => agent_name} = payload, socket) do
    socket =
      socket
      |> assign(:agent_name, agent_name)
      |> assign(:status, payload["status"] || "idle")
      |> assign(:current_task_id, payload["current_task_id"])

    workspace = Accounts.get_workspace_by_id!(socket.assigns.workspace_id, authorize?: false)

    send(self(), :after_join)

    {:ok,
     %{
       workspace_id: socket.assigns.workspace_id,
       agent_max_run_seconds: workspace.agent_max_run_seconds
     }, socket}
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "unauthorized"}}

  @impl true
  def handle_info(:after_join, socket) do
    topic = presence_topic(socket)

    AgentPresence.track(self(), topic, socket.assigns.agent_name, %{
      status: socket.assigns.status,
      current_task_id: socket.assigns.current_task_id,
      agent_name: socket.assigns.agent_name,
      joined_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    push(socket, "presence_state", AgentPresence.list(topic))
    {:noreply, socket}
  end

  @impl true
  def handle_in("update_status", %{"status" => status} = payload, socket) do
    topic = presence_topic(socket)

    AgentPresence.update(self(), topic, socket.assigns.agent_name, fn meta ->
      meta
      |> Map.put(:status, status)
      |> Map.put(:current_task_id, payload["current_task_id"])
    end)

    {:noreply, socket}
  end

  def handle_in("stream_output", %{"run_id" => run_id, "event" => event_data}, socket) do
    case Tasks.create_agent_run_event(
           %{
             event_type: :stream,
             agent_run_id: run_id,
             metadata: normalize_metadata(event_data)
           },
           actor: socket.assigns.current_user,
           tenant: socket.assigns.workspace_id
         ) do
      {:ok, _event} ->
        :ok

      {:error, error} ->
        Logger.warning(
          "AgentChannel failed to persist stream event for run #{run_id}: #{inspect(error)}"
        )
    end

    {:noreply, socket}
  end

  def handle_in("stream_complete", %{"run_id" => _run_id}, socket) do
    {:noreply, socket}
  end

  def handle_in(event, payload, socket) do
    Logger.warning(
      "AgentChannel received unrecognized event: #{event}, payload: #{inspect(payload)}"
    )

    {:noreply, socket}
  end

  defp presence_topic(socket), do: "agents:#{socket.assigns.workspace_id}"

  defp normalize_metadata(event_data) when is_map(event_data), do: event_data

  defp normalize_metadata(event_data) when is_binary(event_data) do
    case Jason.decode(event_data) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{"raw" => event_data}
    end
  end

  defp normalize_metadata(other), do: %{"raw" => inspect(other)}
end
