defmodule CitadelWeb.AgentRunLive do
  @moduledoc false

  use CitadelWeb, :live_view

  alias Citadel.Agent.StreamParser
  alias Citadel.Tasks

  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    workspace = socket.assigns.current_workspace

    run =
      Tasks.get_agent_run!(id,
        actor: user,
        tenant: workspace.id,
        load: [:task]
      )

    socket =
      socket
      |> assign(:run, run)
      |> assign(:page_title, "Agent Run")
      |> stream(:events, [])

    socket =
      if connected?(socket) do
        CitadelWeb.Endpoint.subscribe("tasks:agent_runs:#{run.task_id}")

        if run.status == :running do
          CitadelWeb.Endpoint.subscribe("agent_run_output:#{run.id}")
        end

        socket
      else
        socket
      end

    {:ok, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "agent_run_output:" <> _,
          event: "stream_event",
          payload: %{event: event_data}
        },
        socket
      ) do
    parsed = StreamParser.parse(event_data)
    id = "event-#{System.unique_integer([:positive])}"

    {:noreply, stream_insert(socket, :events, %{id: id, parsed: parsed})}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "agent_run_output:" <> _,
          event: "stream_complete"
        },
        socket
      ) do
    run = reload_run(socket)
    {:noreply, assign(socket, :run, run)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{topic: "tasks:agent_runs:" <> _},
        socket
      ) do
    run = reload_run(socket)
    {:noreply, assign(socket, :run, run)}
  end

  defp reload_run(socket) do
    Tasks.get_agent_run!(socket.assigns.run.id,
      actor: socket.assigns.current_user,
      tenant: socket.assigns.current_workspace.id,
      load: [:task]
    )
  end

  defp status_classes(:pending), do: "bg-base-300/50 text-base-content/60"
  defp status_classes(:running), do: "bg-yellow-500/15 text-yellow-400"
  defp status_classes(:completed), do: "bg-emerald-500/15 text-emerald-400"
  defp status_classes(:failed), do: "bg-red-500/15 text-red-400"
  defp status_classes(:cancelled), do: "bg-orange-500/15 text-orange-400"
  defp status_classes(_), do: "bg-base-300/50 text-base-content/60"

  defp dot_class(:pending), do: "bg-base-content/40"
  defp dot_class(:running), do: "bg-yellow-400 animate-pulse"
  defp dot_class(:completed), do: "bg-emerald-400"
  defp dot_class(:failed), do: "bg-red-400"
  defp dot_class(:cancelled), do: "bg-orange-400"
  defp dot_class(_), do: "bg-base-content/40"

  defp format_timestamp(nil), do: nil

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M:%S")
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_workspace={@current_workspace}
      workspaces={@workspaces}
      agents={@agents}
    >
      <div class="relative h-full p-4 bg-base-200 border border-base-300">
        <div class="h-full overflow-auto flex flex-col">
          <div class="breadcrumbs text-sm mb-4">
            <ul>
              <li><.link navigate={~p"/dashboard"}>Tasks</.link></li>
              <li>
                <.link navigate={~p"/tasks/#{@run.task.human_id}"}>{@run.task.human_id}</.link>
              </li>
              <li><span>Agent Run</span></li>
            </ul>
          </div>

          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-3">
              <h1 class="text-xl font-bold">Agent Run</h1>
              <span class={[
                "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium",
                status_classes(@run.status)
              ]}>
                <span class={["size-1.5 rounded-full", dot_class(@run.status)]} />
                {@run.status}
              </span>
            </div>
          </div>

          <div class="flex flex-wrap gap-x-6 gap-y-1 text-sm text-base-content/60 mb-4">
            <div class="flex items-center gap-1.5">
              <span class="font-medium">Task:</span>
              <.link
                navigate={~p"/tasks/#{@run.task.human_id}"}
                class="text-primary hover:underline"
              >
                {@run.task.human_id} — {@run.task.title}
              </.link>
            </div>
            <div :if={@run.started_at} class="flex items-center gap-1.5">
              <span class="font-medium">Started:</span>
              <span>{format_timestamp(@run.started_at)}</span>
            </div>
            <div :if={@run.completed_at} class="flex items-center gap-1.5">
              <span class="font-medium">Completed:</span>
              <span>{format_timestamp(@run.completed_at)}</span>
            </div>
            <div :if={@run.error_message} class="flex items-center gap-1.5">
              <span class="font-medium text-error">Error:</span>
              <span class="text-error">{@run.error_message}</span>
            </div>
          </div>

          <div class="border-t border-base-300 pt-4 flex-1 min-h-0 flex flex-col">
            <h2 class="text-sm font-semibold text-base-content/70 mb-3">Stream Output</h2>

            <div
              id="agent-run-events"
              phx-update="stream"
              phx-hook="AutoScroll"
              class="flex-1 overflow-y-auto space-y-1 font-mono text-xs bg-base-300/30 rounded-lg p-3 max-h-[calc(100vh-20rem)]"
            >
              <div class="hidden only:block text-base-content/40 italic">
                <%= if @run.status == :running do %>
                  Waiting for events...
                <% else %>
                  No stream events captured for this run.
                <% end %>
              </div>
              <div :for={{id, event} <- @streams.events} id={id}>
                <.render_event event={event.parsed} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp render_event(%{type: :system} = assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <div class="text-blue-400/70 py-0.5">
      <span class="text-blue-400/50">[system]</span>
      {@subtype}
      <span :if={@model} class="text-base-content/40 ml-1">model={@model}</span>
    </div>
    """
  end

  defp render_event(%{type: :assistant, blocks: blocks} = assigns) do
    assigns = assigns |> Map.put(:__changed__, nil) |> Map.put(:blocks, blocks)

    ~H"""
    <div class="py-0.5">
      <div :for={block <- @blocks}>
        <%= cond do %>
          <% block.type == :text -> %>
            <div class="text-base-content/80 whitespace-pre-wrap">{block.text}</div>
          <% block.type == :tool_use -> %>
            <div class="text-purple-400/80">
              <span class="text-purple-400/50">[tool]</span>
              {block.tool}
              <span :if={block.input != %{}} class="text-base-content/40 ml-1">
                {Jason.encode!(block.input) |> String.slice(0, 200)}
              </span>
            </div>
          <% true -> %>
            <div class="text-base-content/40">{inspect(block)}</div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_event(%{type: :tool_result, results: results} = assigns) do
    assigns = assigns |> Map.put(:__changed__, nil) |> Map.put(:results, results)

    ~H"""
    <div class="py-0.5">
      <div :for={result <- @results}>
        <%= if result.type == :tool_result do %>
          <div class={[
            "text-sm",
            if(result.is_error, do: "text-red-400/80", else: "text-emerald-400/70")
          ]}>
            <span class={[
              if(result.is_error, do: "text-red-400/50", else: "text-emerald-400/50")
            ]}>
              [{if result.is_error, do: "error", else: "result"}]
            </span>
            <span class="text-base-content/40 ml-1 truncate inline-block max-w-full align-bottom">
              {truncate_content(result.content)}
            </span>
          </div>
        <% else %>
          <div class="text-base-content/40">{inspect(result)}</div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_event(%{type: :result} = assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <div class="text-cyan-400/70 py-1 border-t border-base-300/50 mt-1">
      <span class="text-cyan-400/50">[result]</span>
      {if @is_error, do: "error", else: @subtype}
      <span :if={@duration_ms} class="text-base-content/40 ml-2">
        {(@duration_ms / 1000) |> Float.round(1)}s
      </span>
      <span :if={@total_cost_usd} class="text-base-content/40 ml-2">
        ${Float.round(@total_cost_usd, 4)}
      </span>
    </div>
    """
  end

  defp render_event(%{type: :error} = assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <div class="text-red-400/70 py-0.5">
      <span class="text-red-400/50">[parse error]</span>
      <span class="text-base-content/40">{@raw}</span>
    </div>
    """
  end

  defp render_event(assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <div class="text-base-content/40 py-0.5">{inspect(assigns |> Map.drop([:__changed__]))}</div>
    """
  end

  defp truncate_content(content) when is_binary(content) do
    if String.length(content) > 300 do
      String.slice(content, 0, 300) <> "..."
    else
      content
    end
  end

  defp truncate_content(content) when is_list(content) do
    content
    |> Enum.map_join(" ", fn
      %{"type" => "text", "text" => text} -> text
      other -> inspect(other)
    end)
    |> truncate_content()
  end

  defp truncate_content(content), do: inspect(content)
end
