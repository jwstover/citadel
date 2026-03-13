defmodule CitadelAgent.Socket do
  @moduledoc """
  Maintains a persistent WebSocket connection to Citadel for presence tracking.
  Joins the agent channel and updates presence metadata when agent status changes.
  """

  use Slipstream

  require Logger

  def start_link(opts \\ []) do
    Slipstream.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def update_status(status, current_task_id \\ nil) do
    GenServer.cast(__MODULE__, {:update_status, status, current_task_id})
  end

  @impl true
  def init(_opts) do
    agent_name = CitadelAgent.config(:agent_name) || "citadel-agent"
    workspace_id = CitadelAgent.config(:workspace_id)

    socket =
      new_socket()
      |> assign(:workspace_id, workspace_id)
      |> assign(:agent_name, agent_name)
      |> connect!(uri: ws_uri())

    {:ok, socket}
  end

  @impl true
  def handle_connect(socket) do
    Logger.info("Connected to Citadel WebSocket, joining agent channel")

    {:ok, join(socket, "agents:lobby", %{"agent_name" => socket.assigns.agent_name})}
  end

  @impl true
  def handle_join(_topic, reply, socket) do
    workspace_id = reply["workspace_id"]
    Logger.info("Joined agent channel for workspace #{workspace_id}")
    {:ok, assign(socket, :workspace_id, workspace_id)}
  end

  @impl true
  def handle_disconnect(_reason, socket) do
    Logger.warning("Disconnected from Citadel WebSocket, will reconnect...")
    reconnect_or_keep(socket)
  end

  @impl true
  def handle_topic_close(_topic, _reason, socket) do
    Logger.warning("Agent channel closed, will rejoin on reconnect...")
    reconnect_or_keep(socket)
  end

  @impl true
  def handle_cast({:update_status, status, current_task_id}, socket) do
    payload = %{
      "status" => status,
      "current_task_id" => current_task_id
    }

    push(socket, "agents:lobby", "update_status", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_message(_topic, _event, _payload, socket) do
    {:ok, socket}
  end

  defp reconnect_or_keep(socket) do
    case reconnect(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, _reason} -> {:ok, socket}
    end
  end

  defp ws_uri do
    base_url = CitadelAgent.config(:citadel_url) || "http://localhost:4000"
    api_key = CitadelAgent.config(:api_key)

    base_url
    |> String.replace(~r{^http}, "ws")
    |> then(&"#{&1}/agent/websocket?token=#{api_key}")
  end
end
