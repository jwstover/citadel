defmodule CitadelWeb.AgentChannel do
  @moduledoc false

  use Phoenix.Channel

  require Logger

  alias Citadel.Tasks.StallDetector
  alias CitadelWeb.AgentPresence

  @impl true
  def join("agents:" <> _, %{"agent_name" => agent_name} = payload, socket) do
    socket =
      socket
      |> assign(:agent_name, agent_name)
      |> assign(:status, payload["status"] || "idle")
      |> assign(:current_task_id, payload["current_task_id"])

    send(self(), :after_join)
    {:ok, %{workspace_id: socket.assigns.workspace_id}, socket}
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
    StallDetector.record_activity(run_id)

    CitadelWeb.Endpoint.broadcast("agent_run_output:#{run_id}", "stream_event", %{
      event: event_data
    })

    {:noreply, socket}
  end

  def handle_in("stream_complete", %{"run_id" => run_id}, socket) do
    CitadelWeb.Endpoint.broadcast("agent_run_output:#{run_id}", "stream_complete", %{})
    {:noreply, socket}
  end

  def handle_in(event, payload, socket) do
    Logger.warning(
      "AgentChannel received unrecognized event: #{event}, payload: #{inspect(payload)}"
    )

    {:noreply, socket}
  end

  defp presence_topic(socket), do: "agents:#{socket.assigns.workspace_id}"
end
