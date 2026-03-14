defmodule CitadelWeb.Components.AgentStatus do
  @moduledoc false

  use CitadelWeb, :html

  attr :agents, :list, required: true

  def agent_status_panel(assigns) do
    ~H"""
    <div id="agent-status-panel" class="flex flex-col gap-2">
      <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-base-content/50 px-1">
        <.icon name="hero-cpu-chip" class="size-3.5" />
        <span>Agents</span>
        <span :if={@agents != []} class="badge badge-xs badge-ghost">{length(@agents)}</span>
      </div>

      <div :if={@agents == []} class="px-1 text-xs text-base-content/40 italic">
        No agents connected
      </div>

      <div
        :for={agent <- @agents}
        id={"agent-#{agent.name}"}
        class="flex items-center gap-2.5 px-2 py-1.5 rounded-lg hover:bg-base-200/50 transition-colors duration-150"
      >
        <span class={[
          "relative flex size-2.5 shrink-0",
          status_pulse_class(agent.status)
        ]}>
          <span class={[
            "absolute inline-flex h-full w-full rounded-full opacity-75",
            if(agent.status == "working", do: "animate-ping bg-warning", else: "hidden")
          ]} />
          <span class={[
            "relative inline-flex rounded-full size-2.5",
            status_dot_class(agent.status)
          ]} />
        </span>

        <div class="flex flex-col min-w-0 flex-1">
          <span class="text-sm font-medium text-base-content truncate">{agent.name}</span>
          <span
            :if={agent.status == "working" && agent.current_task_id && agent.current_task_human_id}
            class="text-xs text-base-content/50 truncate"
          >
            Working on <.link navigate={~p"/tasks/#{agent.current_task_human_id}"} class="underline hover:text-base-content/70">{agent.current_task_human_id}</.link>
          </span>
          <span
            :if={agent.status == "working" && agent.current_task_id && !agent.current_task_human_id}
            class="text-xs text-base-content/50 truncate"
          >
            Working on task
          </span>
          <span :if={agent.status == "idle"} class="text-xs text-base-content/50">
            Idle
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp status_dot_class("idle"), do: "bg-success"
  defp status_dot_class("working"), do: "bg-warning"
  defp status_dot_class(_), do: "bg-base-content/30"

  defp status_pulse_class("working"), do: ""
  defp status_pulse_class(_), do: ""
end
