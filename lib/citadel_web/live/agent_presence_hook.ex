defmodule CitadelWeb.AgentPresenceHook do
  @moduledoc """
  LiveView on_mount hook that subscribes to agent presence for the current workspace.
  Maintains an `@agents` assign with the current list of connected agents.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  require Ash.Query

  alias CitadelWeb.AgentPresence

  def on_mount(:default, _params, _session, socket) do
    workspace = socket.assigns[:current_workspace]

    socket =
      if workspace && connected?(socket) do
        topic = agent_topic(workspace.id)
        Phoenix.PubSub.subscribe(Citadel.PubSub, topic)

        agents =
          AgentPresence.list(topic)
          |> presence_to_agents()
          |> resolve_task_human_ids(workspace.id)

        socket
        |> assign(:agents, agents)
        |> attach_hook(:agent_presence_diff, :handle_info, &handle_presence_info/2)
      else
        assign(socket, :agents, [])
      end

    {:cont, socket}
  end

  defp handle_presence_info(%Phoenix.Socket.Broadcast{topic: "agents:" <> _}, socket) do
    workspace = socket.assigns.current_workspace
    topic = agent_topic(workspace.id)

    agents =
      AgentPresence.list(topic)
      |> presence_to_agents()
      |> resolve_task_human_ids(workspace.id)

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
        current_task_human_id: nil,
        joined_at: meta.joined_at
      }
    end)
    |> Enum.sort_by(& &1.joined_at)
  end

  defp resolve_task_human_ids(agents, workspace_id) do
    task_ids =
      agents
      |> Enum.map(& &1.current_task_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if task_ids == [] do
      agents
    else
      human_ids_by_id =
        Citadel.Tasks.Task
        |> Ash.Query.filter(id in ^task_ids)
        |> Ash.Query.select([:id, :human_id])
        |> Ash.read!(tenant: workspace_id, authorize?: false)
        |> Map.new(&{&1.id, &1.human_id})

      Enum.map(agents, fn agent ->
        %{agent | current_task_human_id: Map.get(human_ids_by_id, agent.current_task_id)}
      end)
    end
  end
end
