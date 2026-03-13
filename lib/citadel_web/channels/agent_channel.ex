defmodule CitadelWeb.AgentChannel do
  @moduledoc false

  use Phoenix.Channel

  alias CitadelWeb.AgentPresence

  @impl true
  def join("agents:" <> workspace_id, %{"agent_name" => agent_name}, socket) do
    if workspace_id == socket.assigns.workspace_id do
      socket = assign(socket, :agent_name, agent_name)
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "unauthorized"}}

  @impl true
  def handle_info(:after_join, socket) do
    AgentPresence.track(socket, socket.assigns.agent_name, %{
      status: "idle",
      current_task_id: nil,
      agent_name: socket.assigns.agent_name,
      joined_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    push(socket, "presence_state", AgentPresence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_in("update_status", %{"status" => status} = payload, socket) do
    AgentPresence.update(socket, socket.assigns.agent_name, fn meta ->
      meta
      |> Map.put(:status, status)
      |> Map.put(:current_task_id, payload["current_task_id"])
    end)

    {:noreply, socket}
  end
end
