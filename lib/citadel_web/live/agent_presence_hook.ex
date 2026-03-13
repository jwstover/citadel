defmodule CitadelWeb.AgentPresenceHook do
  @moduledoc """
  LiveView on_mount hook that subscribes to agent presence for the current workspace.
  Maintains an `@agents` assign with the current list of connected agents.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias CitadelWeb.AgentPresence

  def on_mount(:default, _params, _session, socket) do
    workspace = socket.assigns[:current_workspace]

    socket =
      if workspace && connected?(socket) do
        topic = agent_topic(workspace.id)
        Phoenix.PubSub.subscribe(Citadel.PubSub, topic)

        agents = presence_to_agents(AgentPresence.list(topic))

        socket
        |> assign(:agents, agents)
        |> attach_hook(:agent_presence_diff, :handle_info, &handle_presence_info/2)
      else
        assign(socket, :agents, [])
      end

    {:cont, socket}
  end

  defp handle_presence_info(%Phoenix.Socket.Broadcast{topic: "agents:" <> _}, socket) do
    topic = agent_topic(socket.assigns.current_workspace.id)
    agents = presence_to_agents(AgentPresence.list(topic))
    {:halt, assign(socket, :agents, agents)}
  end

  defp handle_presence_info(_message, socket), do: {:cont, socket}

  defp agent_topic(workspace_id), do: "agents:#{workspace_id}"

  defp presence_to_agents(presences) do
    presences
    |> Enum.map(fn {name, %{metas: [meta | _]}} ->
      %{
        name: name,
        status: meta.status,
        current_task_id: meta.current_task_id,
        joined_at: meta.joined_at
      }
    end)
    |> Enum.sort_by(& &1.joined_at)
  end
end
