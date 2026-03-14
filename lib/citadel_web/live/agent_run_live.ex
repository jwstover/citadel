defmodule CitadelWeb.AgentRunLive do
  @moduledoc false

  use CitadelWeb, :live_view

  import CitadelWeb.Components.Markdown

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
      |> assign(:pending_tools, %{})
      |> assign(:todos, [])
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
    {:noreply, process_event(parsed, socket)}
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

  defp process_event(%{type: :assistant, blocks: blocks} = event, socket) do
    {text_blocks, tool_blocks} = Enum.split_with(blocks, &(&1.type != :tool_use))
    {todo_blocks, visible_tool_blocks} = Enum.split_with(tool_blocks, &todo_tool?/1)

    socket =
      if text_blocks != [] do
        id = "event-#{System.unique_integer([:positive])}"

        stream_insert(socket, :events, %{
          id: id,
          parsed: %{type: :assistant_text, blocks: text_blocks, model: event[:model]}
        })
      else
        socket
      end

    socket =
      Enum.reduce(todo_blocks, socket, fn block, sock ->
        pending = Map.put(sock.assigns.pending_tools, block.id, block)
        sock = assign(sock, :pending_tools, pending)

        case block do
          %{tool: "TodoWrite", input: %{"todos" => todos}} when is_list(todos) ->
            assign(sock, :todos, todos)

          _ ->
            sock
        end
      end)

    Enum.reduce(visible_tool_blocks, socket, fn block, sock ->
      tool_id = block.id
      pending = Map.put(sock.assigns.pending_tools, tool_id, block)
      sock = assign(sock, :pending_tools, pending)

      stream_insert(sock, :events, %{
        id: tool_id,
        parsed: %{type: :tool_call, tool: block.tool, input: block.input, result: nil}
      })
    end)
  end

  defp process_event(%{type: :tool_result, results: results}, socket) do
    Enum.reduce(results, socket, fn result, sock ->
      tool_use_id = result[:tool_use_id]
      pending = sock.assigns.pending_tools

      if tool_use_id && Map.has_key?(pending, tool_use_id) do
        tool = pending[tool_use_id]
        sock = assign(sock, :pending_tools, Map.delete(pending, tool_use_id))

        if todo_tool?(tool) do
          sock
        else
          stream_insert(sock, :events, %{
            id: tool_use_id,
            parsed: %{type: :tool_call, tool: tool.tool, input: tool.input, result: result}
          })
        end
      else
        id = "event-#{System.unique_integer([:positive])}"

        stream_insert(sock, :events, %{
          id: id,
          parsed: %{type: :tool_result_orphan, result: result}
        })
      end
    end)
  end

  defp process_event(%{type: :system, subtype: "task_progress", tasks: tasks}, socket)
       when is_list(tasks) do
    assign(socket, :todos, tasks)
  end

  defp process_event(%{type: :system, subtype: "task_progress"}, socket), do: socket
  defp process_event(%{type: :system, subtype: "task_started"}, socket), do: socket

  defp process_event(parsed, socket) do
    id = "event-#{System.unique_integer([:positive])}"
    stream_insert(socket, :events, %{id: id, parsed: parsed})
  end

  defp todo_tool?(%{tool: "TodoWrite"}), do: true
  defp todo_tool?(%{tool: "TodoRead"}), do: true
  defp todo_tool?(_), do: false

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
              class={[
                "flex-1 overflow-y-auto space-y-1 font-mono text-xs p-3",
                if(@todos == [], do: "max-h-[calc(100vh-20rem)]", else: "max-h-[calc(100vh-32rem)]")
              ]}
            >
              <div class="hidden only:block text-base-content/40 italic">
                <%= if @run.status == :running do %>
                  Waiting for events...
                <% else %>
                  No stream events captured for this run.
                <% end %>
              </div>
              <div :for={{id, event} <- @streams.events} id={id}>
                <.render_event {event.parsed} />
              </div>
            </div>

            <.todo_panel :if={@todos != []} todos={@todos} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp todo_panel(assigns) do
    {completed, remaining} = Enum.split_with(assigns.todos, &(&1["status"] == "completed"))
    total = length(assigns.todos)
    done = length(completed)
    progress = if total > 0, do: round(done / total * 100), else: 0

    assigns =
      assigns
      |> Map.put(:remaining, remaining)
      |> Map.put(:completed, completed)
      |> Map.put(:total, total)
      |> Map.put(:done, done)
      |> Map.put(:progress, progress)

    ~H"""
    <div class="border-t border-base-300 pt-3 mt-3 shrink-0">
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-xs font-semibold text-base-content/70 uppercase tracking-wider">
          Agent Progress
        </h3>
        <span class="text-xs text-base-content/50">{@done}/{@total}</span>
      </div>

      <progress class="progress progress-primary w-full h-1.5 mb-3" value={@progress} max="100" />

      <ul class="space-y-1 text-xs max-h-40 overflow-y-auto">
        <li :for={todo <- @remaining} class="flex items-start gap-2">
          <span class={[
            "shrink-0 mt-0.5 size-3.5 rounded border flex items-center justify-center",
            todo_status_classes(todo["status"])
          ]}>
            <span :if={todo["status"] == "in_progress"} class="size-1.5 rounded-full bg-yellow-400 animate-pulse" />
          </span>
          <span class={[
            "flex-1",
            if(todo["status"] == "in_progress", do: "text-base-content/80", else: "text-base-content/50")
          ]}>
            {todo["content"]}
          </span>
          <span :if={todo["priority"] == "high"} class="text-[9px] text-orange-400/70 uppercase shrink-0">
            high
          </span>
        </li>
        <li :for={todo <- @completed} class="flex items-start gap-2 text-base-content/30">
          <span class="shrink-0 mt-0.5 size-3.5 rounded border border-emerald-500/30 bg-emerald-500/10 flex items-center justify-center text-emerald-400">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="size-2.5">
              <path fill-rule="evenodd" d="M12.416 3.376a.75.75 0 0 1 .208 1.04l-5 7.5a.75.75 0 0 1-1.154.114l-3-3a.75.75 0 0 1 1.06-1.06l2.353 2.353 4.493-6.74a.75.75 0 0 1 1.04-.207Z" clip-rule="evenodd" />
            </svg>
          </span>
          <span class="flex-1 line-through">{todo["content"]}</span>
        </li>
      </ul>
    </div>
    """
  end

  defp todo_status_classes("in_progress"), do: "border-yellow-500/40 bg-yellow-500/10"
  defp todo_status_classes("pending"), do: "border-base-content/20"
  defp todo_status_classes(_), do: "border-base-content/20"

  defp render_event(%{type: :system} = assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <div class="rounded-lg bg-blue-500/5 border border-blue-500/20 px-3 py-2">
      <div class="flex items-center gap-2 text-blue-400/70">
        <span class="text-[10px] font-semibold uppercase tracking-wider text-blue-400/50">system</span>
        <span>{@subtype}</span>
        <span :if={@model} class="text-base-content/40 ml-auto">model={@model}</span>
      </div>
    </div>
    """
  end

  defp render_event(%{type: :assistant_text} = assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <div class="rounded-lg bg-base-300/40 border border-base-300 px-3 py-2">
      <div class="text-[10px] font-semibold uppercase tracking-wider text-base-content/40 mb-1.5">
        assistant
        <span :if={@model} class="font-normal normal-case tracking-normal ml-1">{@model}</span>
      </div>
      <div class="space-y-1">
        <div :for={block <- @blocks}>
          <%= case block.type do %>
            <% :text -> %>
              <div class="prose prose-sm prose-invert max-w-none text-base-content/80">{to_markdown(block.text)}</div>
            <% :thinking -> %>
              <div class="text-base-content/40 italic whitespace-pre-wrap">{block.text}</div>
            <% _ -> %>
              <div class="text-base-content/40">{inspect(block)}</div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp render_event(%{type: :tool_call, result: nil} = assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <details class="group">
      <summary class="flex items-center gap-2 cursor-pointer list-none py-1.5 [&::-webkit-details-marker]:hidden">
        <span class="shrink-0 inline-block size-1.5 rounded-full bg-yellow-400 animate-pulse" />
        <span class="font-semibold text-purple-400/80">{@tool}</span>
        <span :if={format_tool_description(@tool, @input)} class="text-base-content/50 truncate">
          {format_tool_description(@tool, @input)}
        </span>
        <svg
          class="shrink-0 ml-auto size-3 text-base-content/30 transition-transform group-open:rotate-180"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M5.22 8.22a.75.75 0 0 1 1.06 0L10 11.94l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.22 9.28a.75.75 0 0 1 0-1.06Z"
            clip-rule="evenodd"
          />
        </svg>
      </summary>
      <div :if={@input != %{}} class="pl-5 text-base-content/40 break-all">
        <pre class="whitespace-pre-wrap text-xs">{format_tool_detail(@tool, @input)}</pre>
      </div>
    </details>
    """
  end

  defp render_event(%{type: :tool_call, result: result} = assigns) do
    assigns = assigns |> Map.put(:__changed__, nil) |> Map.put(:result, result)

    ~H"""
    <details class="group">
      <summary class="flex items-center gap-2 cursor-pointer list-none py-1.5 [&::-webkit-details-marker]:hidden">
        <span class="font-semibold text-purple-400/80">{@tool}</span>
        <span :if={format_tool_description(@tool, @input)} class="text-base-content/50 truncate">
          {format_tool_description(@tool, @input)}
        </span>
        <span
          :if={@result.is_error}
          class="shrink-0 inline-block rounded bg-red-500/15 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-red-400"
        >
          error
        </span>
        <svg
          class="shrink-0 ml-auto size-3 text-base-content/30 transition-transform group-open:rotate-180"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M5.22 8.22a.75.75 0 0 1 1.06 0L10 11.94l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.22 9.28a.75.75 0 0 1 0-1.06Z"
            clip-rule="evenodd"
          />
        </svg>
      </summary>
      <div class="pl-5">
        <div :if={@input != %{}} class="text-base-content/40 break-all">
          <pre class="whitespace-pre-wrap text-xs">{format_tool_detail(@tool, @input)}</pre>
        </div>
        <div class={[
          "mt-1 pt-1 border-t break-all",
          if(@result.is_error,
            do: "border-red-500/20 text-red-400/70",
            else: "border-base-300/50 text-base-content/50"
          )
        ]}>
          {truncate_content(@result.content)}
        </div>
      </div>
    </details>
    """
  end

  defp render_event(%{type: :tool_result_orphan} = assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <div class="rounded-lg bg-emerald-500/5 border border-emerald-500/20 px-3 py-2">
      <div class="text-[10px] font-semibold uppercase tracking-wider text-emerald-400/50 mb-1.5">
        tool result
      </div>
      <div class={if(Map.get(@result, :is_error), do: "text-red-400/70", else: "text-base-content/50")}>
        {truncate_content(Map.get(@result, :content, @result[:raw] || @result))}
      </div>
    </div>
    """
  end

  defp render_event(%{type: :result} = assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <div class="rounded-lg bg-cyan-500/10 border border-cyan-500/20 px-3 py-2">
      <div class="flex items-center gap-2 text-cyan-400/70">
        <span class="text-[10px] font-semibold uppercase tracking-wider text-cyan-400/50">result</span>
        <span>{if @is_error, do: "error", else: @subtype}</span>
        <div class="ml-auto flex items-center gap-3 text-base-content/40">
          <span :if={@duration_ms}>
            {(@duration_ms / 1000) |> Float.round(1)}s
          </span>
          <span :if={@total_cost_usd}>
            ${Float.round(@total_cost_usd, 4)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp render_event(%{type: :error} = assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <div class="rounded-lg bg-red-500/10 border border-red-500/20 px-3 py-2">
      <div class="text-[10px] font-semibold uppercase tracking-wider text-red-400/50 mb-1">parse error</div>
      <div class="text-base-content/40 break-all">{@raw}</div>
    </div>
    """
  end

  defp render_event(assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    ~H"""
    <div class="rounded-lg bg-base-300/30 border border-base-300 px-3 py-2">
      <div class="text-base-content/40 break-all">{inspect(assigns |> Map.drop([:__changed__]))}</div>
    </div>
    """
  end

  defp format_tool_description("Bash", %{"description" => desc}) when is_binary(desc), do: desc
  defp format_tool_description("Bash", %{"command" => cmd}), do: String.slice(cmd, 0, 80)
  defp format_tool_description("Read", %{"file_path" => path}), do: path
  defp format_tool_description("Write", %{"file_path" => path}), do: path
  defp format_tool_description("Edit", %{"file_path" => path}), do: path
  defp format_tool_description("Glob", %{"pattern" => pattern}), do: pattern

  defp format_tool_description("Grep", %{"pattern" => pattern} = input) do
    path = input["path"]
    if path, do: "#{pattern} in #{path}", else: pattern
  end

  defp format_tool_description("Agent", %{"prompt" => prompt} = input) do
    type = input["subagent_type"]
    prefix = if type, do: "[#{type}] ", else: ""
    "#{prefix}#{String.slice(prompt, 0, 100)}"
  end

  defp format_tool_description(_tool, _input), do: nil

  defp format_tool_detail("Bash", %{"command" => cmd}), do: "$ #{cmd}"
  defp format_tool_detail("Read", %{"file_path" => path}), do: path

  defp format_tool_detail("Edit", %{"file_path" => path} = input) do
    old = input["old_string"]
    new = input["new_string"]

    parts = [path]
    parts = if old, do: parts ++ ["\n--- old\n#{old}"], else: parts
    parts = if new, do: parts ++ ["\n+++ new\n#{new}"], else: parts
    Enum.join(parts)
  end

  defp format_tool_detail("Write", %{"file_path" => path}), do: path

  defp format_tool_detail("Grep", %{"pattern" => pattern} = input) do
    path = input["path"]
    if path, do: "#{pattern} in #{path}", else: pattern
  end

  defp format_tool_detail("Agent", %{"prompt" => prompt} = input) do
    type = input["subagent_type"]
    prefix = if type, do: "[#{type}] ", else: ""
    "#{prefix}#{prompt}"
  end

  defp format_tool_detail(_tool, input) do
    Jason.encode!(input, pretty: true)
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
