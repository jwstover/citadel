defmodule CitadelWeb.Components.TaskActivitySection do
  @moduledoc false

  use CitadelWeb, :live_component

  alias Citadel.Tasks
  alias CitadelWeb.Components.Markdown

  import CitadelWeb.Components.TaskComponents, only: [user_avatar: 1]

  def update(%{broadcast: broadcast}, socket) do
    {:ok, handle_broadcast(broadcast, socket)}
  end

  def update(%{agent_run_updated: _broadcast}, socket) do
    {:ok, reload_agent_run_activities(socket)}
  end

  def update(assigns, socket) do
    {activities, assigns} = Map.pop(assigns, :activities, [])
    socket = assign(socket, assigns)

    socket =
      if socket.assigns[:activities_loaded] do
        socket
      else
        socket
        |> assign(:activities, sort_newest_first(activities))
        |> assign(:activities_loaded, true)
        |> assign(:form, to_form(%{"body" => ""}, as: :comment))
        |> assign(:request_changes, false)
        |> assign(:reply_to_activity_id, nil)
      end

    {:ok, socket}
  end

  defp handle_broadcast(
         %Phoenix.Socket.Broadcast{event: event, payload: %{data: activity}},
         socket
       )
       when event in [
              "create_comment",
              "create_request_changes_comment",
              "create_agent_question",
              "create_question_response"
            ] do
    activity =
      Ash.load!(activity, [:user],
        tenant: socket.assigns.current_workspace.id,
        actor: socket.assigns.current_user
      )

    upsert_activity(socket, activity)
  end

  defp handle_broadcast(
         %Phoenix.Socket.Broadcast{
           event: "create_agent_run_activity",
           payload: %{data: activity}
         },
         socket
       ) do
    activity =
      Ash.load!(activity, [:user, :agent_run],
        tenant: socket.assigns.current_workspace.id,
        actor: socket.assigns.current_user
      )

    upsert_activity(socket, activity)
  end

  defp handle_broadcast(
         %Phoenix.Socket.Broadcast{event: "destroy_comment", payload: %{data: activity}},
         socket
       ) do
    activities = Enum.reject(socket.assigns.activities, &(&1.id == activity.id))
    assign(socket, :activities, activities)
  end

  defp upsert_activity(socket, activity) do
    activities =
      socket.assigns.activities
      |> Enum.reject(&(&1.id == activity.id))
      |> List.insert_at(0, activity)
      |> sort_newest_first()

    assign(socket, :activities, activities)
  end

  defp reload_agent_run_activities(socket) do
    activities =
      Tasks.list_task_activities!(socket.assigns.task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:user, :agent_run]
      )

    Enum.reduce(activities, socket, fn activity, acc ->
      if activity.type == :agent_run, do: upsert_activity(acc, activity), else: acc
    end)
  end

  def handle_event("toggle-request-changes", _params, socket) do
    {:noreply, assign(socket, :request_changes, !socket.assigns.request_changes)}
  end

  def handle_event("toggle-reply", %{"id" => id}, socket) do
    reply_to = if socket.assigns.reply_to_activity_id == id, do: nil, else: id
    {:noreply, assign(socket, :reply_to_activity_id, reply_to)}
  end

  def handle_event("submit-comment", %{"comment" => %{"body" => body}}, socket) do
    body = String.trim(body)

    if body == "" do
      {:noreply, socket}
    else
      opts = [actor: socket.assigns.current_user, tenant: socket.assigns.current_workspace.id]

      activity =
        cond do
          socket.assigns.reply_to_activity_id ->
            Tasks.create_question_response!(
              %{
                body: body,
                task_id: socket.assigns.task.id,
                parent_activity_id: socket.assigns.reply_to_activity_id
              },
              opts
            )

          socket.assigns.request_changes ->
            Tasks.create_request_changes_comment!(
              %{body: body, task_id: socket.assigns.task.id},
              opts
            )

          true ->
            Tasks.create_comment!(%{body: body, task_id: socket.assigns.task.id}, opts)
        end

      activity =
        Ash.load!(activity, [:user],
          tenant: socket.assigns.current_workspace.id,
          actor: socket.assigns.current_user
        )

      socket =
        socket
        |> upsert_activity(activity)
        |> assign(:form, to_form(%{"body" => ""}, as: :comment))
        |> assign(:request_changes, false)
        |> assign(:reply_to_activity_id, nil)

      {:noreply, socket}
    end
  end

  def handle_event("delete-comment", %{"id" => activity_id}, socket) do
    activity =
      Ash.get!(Citadel.Tasks.TaskActivity, activity_id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    Tasks.destroy_comment!(activity,
      actor: socket.assigns.current_user,
      tenant: socket.assigns.current_workspace.id
    )

    activities = Enum.reject(socket.assigns.activities, &(&1.id == activity.id))
    {:noreply, assign(socket, :activities, activities)}
  end

  def handle_event("request-cancel-agent-run", %{"run-id" => run_id}, socket) do
    send(self(), {:request_cancel_agent_run, run_id})
    {:noreply, socket}
  end

  defp sort_newest_first(activities) do
    Enum.sort_by(activities, & &1.inserted_at, {:desc, DateTime})
  end

  defp group_by_day(activities) do
    activities
    |> Enum.group_by(&day_key(&1.inserted_at))
    |> Enum.sort_by(fn {key, _} -> key end, :desc)
  end

  defp day_key(dt) do
    dt
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp day_label(dt) do
    today = Date.utc_today()
    date = DateTime.to_date(dt)

    case Date.diff(today, date) do
      0 -> "Today"
      1 -> "Yesterday"
      _ -> Calendar.strftime(date, "%b %-d")
    end
  end

  def render(assigns) do
    assigns =
      assign(assigns, :grouped_activities, group_by_day(assigns.activities))

    ~H"""
    <div id={@id} class="py-6 border-t border-base-300 max-w-5xl">
      <div class="flex items-center justify-between mb-6">
        <h2 class="font-mono text-xs font-semibold uppercase tracking-[0.08em] text-base-content/70">
          Activity
        </h2>
        <span class="font-mono text-[11px] text-base-content/50">
          {activity_count_label(@activities)}
        </span>
      </div>

      <.stream_composer
        id={@id}
        form={@form}
        request_changes={@request_changes}
        reply_to_activity_id={@reply_to_activity_id}
        current_user={@current_user}
        myself={@myself}
      />

      <%= if @activities == [] do %>
        <p class="text-base-content/50 italic text-sm pl-11 pt-2">No activity yet.</p>
      <% else %>
        <%= for {{_day_key, items}, gi} <- Enum.with_index(@grouped_activities) do %>
          <% first_dt = hd(items).inserted_at %>
          <div class={["pb-1", gi > 0 && "mt-4"]}>
            <div class="flex items-center gap-3 ml-7 mb-3">
              <span class="font-mono text-[11px] uppercase tracking-[0.1em] text-base-content/50">
                {day_label(first_dt)}
              </span>
              <span class="flex-1 h-px bg-base-300"></span>
              <span class="font-mono text-[11px] text-base-content/40">{length(items)}</span>
            </div>

            <%= for {activity, idx} <- Enum.with_index(items) do %>
              <.stream_item
                activity={activity}
                first={gi == 0 and idx == 0}
                last={gi == length(@grouped_activities) - 1 and idx == length(items) - 1}
                current_user={@current_user}
                can_edit={@can_edit}
                myself={@myself}
              />
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :form, :any, required: true
  attr :request_changes, :boolean, required: true
  attr :reply_to_activity_id, :any, required: true
  attr :current_user, :any, required: true
  attr :myself, :any, required: true

  defp stream_composer(assigns) do
    ~H"""
    <.form
      for={@form}
      id={"#{@id}-form"}
      phx-submit="submit-comment"
      phx-target={@myself}
      class="mb-6 rounded-lg border border-base-300 bg-base-100/40 p-3"
    >
      <div class="flex gap-3 items-start">
        <.user_avatar user={@current_user} size="w-6 h-6" />
        <div class="flex-1 min-w-0">
          <div
            :if={@reply_to_activity_id}
            class="flex items-center justify-between bg-purple-500/10 text-purple-300 text-xs px-3 py-1.5 rounded-t-md border border-b-0 border-purple-400/20 -mt-1 -mx-1 mb-2"
          >
            <span>Replying to agent question</span>
            <button
              type="button"
              phx-click="toggle-reply"
              phx-target={@myself}
              phx-value-id={@reply_to_activity_id}
              class="hover:text-purple-200"
            >
              <.icon name="hero-x-mark" class="size-3.5" />
            </button>
          </div>
          <textarea
            name={@form[:body].name}
            rows="2"
            placeholder={composer_placeholder(@reply_to_activity_id, @request_changes)}
            class="w-full bg-transparent text-sm text-base-content placeholder:text-base-content/40 resize-none focus:outline-none leading-relaxed"
            id={"#{@id}-body"}
            phx-hook="CmdEnterSubmit"
          >{@form[:body].value}</textarea>

          <div class="flex items-center justify-between mt-2 gap-3 flex-wrap">
            <label
              :if={!@reply_to_activity_id}
              class="inline-flex items-center gap-2 cursor-pointer select-none font-sans text-xs text-base-content/60"
            >
              <input
                type="checkbox"
                checked={@request_changes}
                phx-click="toggle-request-changes"
                phx-target={@myself}
                class="checkbox checkbox-warning checkbox-xs"
              />
              <span class={[
                @request_changes && "text-warning font-medium"
              ]}>
                Request changes
              </span>
              <span :if={@request_changes} class="text-base-content/40 text-[11px]">
                — queues a new agent run
              </span>
            </label>
            <div :if={@reply_to_activity_id} class="flex-1" />

            <button
              type="submit"
              class={[
                "btn btn-sm font-sans font-medium",
                cond do
                  @reply_to_activity_id -> "btn-primary"
                  @request_changes -> "btn-warning"
                  true -> "btn-neutral"
                end
              ]}
            >
              {composer_submit_label(@reply_to_activity_id, @request_changes)}
            </button>
          </div>
        </div>
      </div>
    </.form>
    """
  end

  defp composer_placeholder(reply_id, request_changes) do
    cond do
      reply_id -> "Type your reply to the agent's question…"
      request_changes -> "Describe what changes are needed…"
      true -> "Leave a comment… (markdown supported)"
    end
  end

  defp composer_submit_label(reply_id, request_changes) do
    cond do
      reply_id -> "Reply"
      request_changes -> "Comment & queue run"
      true -> "Comment"
    end
  end

  attr :activity, :map, required: true
  attr :first, :boolean, required: true
  attr :last, :boolean, required: true
  attr :current_user, :any, required: true
  attr :can_edit, :boolean, required: true
  attr :myself, :any, required: true

  defp stream_item(assigns) do
    %{label: pill_label, color: pill_color, soft: pill_soft, pulse: pulse?} =
      status_meta(assigns.activity)

    assigns =
      assigns
      |> assign(:pill_label, pill_label)
      |> assign(:pill_color, pill_color)
      |> assign(:pill_soft, pill_soft)
      |> assign(:pulse?, pulse?)
      |> assign(:run, assigns.activity.agent_run)

    ~H"""
    <div class="flex items-start group">
      <div class="relative w-7 flex-none self-stretch">
        <span class="absolute" style={rail_line_style(@first, @last)} />
        <span
          class={["absolute rounded-full", @pulse? && "stream-dot-pulse"]}
          style={rail_dot_style(@pill_color)}
        />
      </div>

      <div class="flex-1 min-w-0 pb-5 pl-1">
        <div class="flex items-center gap-3 flex-wrap">
          <.activity_avatar activity={@activity} />
          <span class="font-mono text-[13px] font-medium text-base-content">
            {actor_short_name(@activity)}
          </span>
          <.status_pill label={@pill_label} color={@pill_color} soft={@pill_soft} />

          <span class="flex-1"></span>

          <span
            :if={
              @activity.type == :agent_run and not is_nil(@run) and not is_nil(@run.started_at) and
                not is_nil(@run.completed_at)
            }
            class="font-mono text-[11px] text-base-content/50"
          >
            {format_duration(@run.started_at, @run.completed_at)}
          </span>
          <span
            class="font-mono text-[11px] text-base-content/50"
            title={Calendar.strftime(@activity.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
          >
            {relative_time(@activity.inserted_at)}
          </span>
        </div>

        <.activity_body
          activity={@activity}
          run={@run}
          current_user={@current_user}
          can_edit={@can_edit}
          myself={@myself}
        />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :color, :string, required: true
  attr :soft, :string, required: true

  defp status_pill(assigns) do
    ~H"""
    <span
      :if={@label}
      class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full font-mono text-[11px] font-medium"
      style={"background: #{@soft}; color: #{@color};"}
    >
      <span
        class="size-1.5 rounded-full flex-none"
        style={"background: #{@color};"}
      />
      {@label}
    </span>
    """
  end

  attr :activity, :map, required: true
  attr :run, :any, required: true
  attr :current_user, :any, required: true
  attr :can_edit, :boolean, required: true
  attr :myself, :any, required: true

  defp activity_body(%{activity: %{type: :agent_run}} = assigns) do
    ~H"""
    <%= if @run do %>
      <p
        :if={@run.error_message}
        class="mt-2 text-[13.5px] leading-relaxed text-base-content/70 max-w-2xl"
      >
        <span :if={@run.status == :failed} class="text-error font-mono mr-1.5">✗</span>
        {@run.error_message}
      </p>

      <p
        :if={is_nil(@run.error_message) and @run.status == :running and not is_nil(@run.session_id)}
        class="mt-2 text-[13.5px] leading-relaxed text-base-content/60 max-w-2xl font-mono text-xs"
      >
        session {String.slice(@run.session_id, 0..7)}…
      </p>

      <details
        :if={is_list(@run.commits) and @run.commits != []}
        class="mt-3 max-w-2xl group/commits"
      >
        <summary class="font-mono text-[11px] text-info hover:text-info/80 cursor-pointer select-none inline-flex items-center gap-1.5 list-none">
          <.icon name="hero-chevron-right" class="size-3" /> Commits ({length(@run.commits)})
        </summary>
        <div class="mt-2 ml-1 pl-3 border-l border-base-300 flex flex-col gap-1">
          <div
            :for={commit <- @run.commits}
            class="flex items-center gap-2 font-mono text-[12px] py-0.5"
          >
            <span class="text-purple-300 min-w-[60px]">
              {String.slice(commit["sha"] || "", 0..6)}
            </span>
            <span class="text-base-content/70 truncate">{commit["message"]}</span>
          </div>
        </div>
      </details>

      <details
        :if={@run.test_output && @run.test_output != ""}
        class="mt-2 max-w-2xl group/output"
      >
        <summary class="font-mono text-[11px] text-info hover:text-info/80 cursor-pointer select-none inline-flex items-center gap-1.5 list-none">
          <.icon name="hero-chevron-right" class="size-3" /> Test Output
        </summary>
        <pre class="mt-2 p-3 bg-black border border-base-300 rounded-md font-mono text-[11.5px] leading-relaxed text-base-content/70 whitespace-pre-wrap max-h-96 overflow-auto"><code>{@run.test_output}</code></pre>
      </details>

      <div class="mt-2 flex items-center gap-4 flex-wrap">
        <.link
          navigate={~p"/agent-runs/#{@run.id}"}
          class="font-mono text-[11px] text-info hover:text-info/80 inline-flex items-center gap-1"
        >
          <.icon name="hero-arrow-top-right-on-square" class="size-3" />
          {if @run.status == :running, do: "Watch", else: "View"}
        </.link>

        <button
          :if={@can_edit and @run.status in [:pending, :running]}
          phx-click="request-cancel-agent-run"
          phx-target={@myself}
          phx-value-run-id={@run.id}
          class="font-mono text-[11px] text-base-content/50 hover:text-error inline-flex items-center gap-1"
        >
          <.icon name="hero-x-mark" class="size-3" /> Cancel
        </button>
      </div>
    <% else %>
      <p class="mt-2 text-[13.5px] text-base-content/50 italic">Agent run no longer available.</p>
    <% end %>
    """
  end

  defp activity_body(%{activity: %{type: type}} = assigns)
       when type in [:comment, :change_request, :question, :question_response] do
    ~H"""
    <div class="mt-2 max-w-2xl prose prose-sm prose-invert">
      {Markdown.to_markdown(@activity.body || "")}
    </div>

    <div class="mt-1 flex items-center gap-3 opacity-0 group-hover:opacity-100 transition-opacity">
      <button
        :if={@activity.type == :question}
        phx-click="toggle-reply"
        phx-target={@myself}
        phx-value-id={@activity.id}
        class="font-mono text-[11px] text-purple-300 hover:text-purple-200 inline-flex items-center gap-1"
      >
        <.icon name="hero-chat-bubble-left" class="size-3" /> reply
      </button>
      <button
        :if={@activity.user_id == @current_user.id}
        phx-click="delete-comment"
        phx-target={@myself}
        phx-value-id={@activity.id}
        data-confirm="Delete this comment?"
        class="font-mono text-[11px] text-base-content/40 hover:text-error inline-flex items-center gap-1"
      >
        <.icon name="hero-trash" class="size-3" /> delete
      </button>
    </div>
    """
  end

  attr :activity, :map, required: true

  defp activity_avatar(%{activity: %{actor_type: :user, user: user}} = assigns)
       when not is_nil(user) do
    assigns = assign(assigns, :user, user)

    ~H"""
    <.user_avatar user={@user} size="w-6 h-6" />
    """
  end

  defp activity_avatar(%{activity: %{actor_type: type}} = assigns) when type in [:ai, :system] do
    ~H"""
    <div
      class="w-6 h-6 rounded-[6px] border border-base-content/20 bg-base-100 flex items-center justify-center text-base-content/70"
      title="Agent"
    >
      <.icon name="hero-cpu-chip" class="size-3.5" />
    </div>
    """
  end

  defp activity_avatar(assigns) do
    ~H"""
    <div class="w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-[10px] text-base-content/60">
      ?
    </div>
    """
  end

  defp actor_short_name(%{actor_type: :user, user: %{email: email}}) when not is_nil(email) do
    email
    |> to_string()
    |> String.split("@")
    |> List.first()
  end

  defp actor_short_name(%{actor_display_name: name}) when not is_nil(name), do: name
  defp actor_short_name(%{actor_type: :ai}), do: "agent"
  defp actor_short_name(%{actor_type: :system}), do: "system"
  defp actor_short_name(_), do: "unknown"

  defp activity_count_label(activities) do
    total = length(activities)
    running = Enum.count(activities, &agent_running?/1)

    cond do
      total == 0 -> "0 events"
      running > 0 -> "#{total} events · #{running} active"
      true -> "#{total} events"
    end
  end

  defp agent_running?(%{type: :agent_run, agent_run: %{status: status}})
       when status in [:running, :pending, :input_requested],
       do: true

  defp agent_running?(_), do: false

  defp status_meta(%{type: :agent_run, agent_run: %{status: :running}}),
    do: %{label: "running", color: "var(--p-blue)", soft: "var(--p-blue-soft)", pulse: true}

  defp status_meta(%{type: :agent_run, agent_run: %{status: :pending}}),
    do: %{label: "pending", color: "var(--p-blue)", soft: "var(--p-blue-soft)", pulse: false}

  defp status_meta(%{type: :agent_run, agent_run: %{status: :completed}}),
    do: %{label: "completed", color: "var(--p-teal)", soft: "var(--p-teal-soft)", pulse: false}

  defp status_meta(%{type: :agent_run, agent_run: %{status: :failed}}),
    do: %{label: "failed", color: "var(--p-red)", soft: "var(--p-red-soft)", pulse: false}

  defp status_meta(%{type: :agent_run, agent_run: %{status: :cancelled}}),
    do: %{
      label: "cancelled",
      color: "var(--p-orange)",
      soft: "var(--p-orange-soft)",
      pulse: false
    }

  defp status_meta(%{type: :agent_run, agent_run: %{status: :input_requested}}),
    do: %{
      label: "awaiting input",
      color: "var(--p-violet)",
      soft: "rgba(179, 157, 240, 0.15)",
      pulse: true
    }

  defp status_meta(%{type: :agent_run}),
    do: %{label: "agent run", color: "var(--p-blue)", soft: "var(--p-blue-soft)", pulse: false}

  defp status_meta(%{type: :change_request}),
    do: %{
      label: "changes requested",
      color: "var(--p-amber)",
      soft: "var(--p-amber-soft)",
      pulse: false
    }

  defp status_meta(%{type: :question}),
    do: %{
      label: "question",
      color: "var(--p-violet)",
      soft: "rgba(179, 157, 240, 0.15)",
      pulse: false
    }

  defp status_meta(%{type: :question_response}),
    do: %{label: "reply", color: "var(--p-teal)", soft: "var(--p-teal-soft)", pulse: false}

  defp status_meta(_),
    do: %{label: nil, color: "var(--color-base-content)", soft: "transparent", pulse: false}

  defp format_duration(%DateTime{} = started, %DateTime{} = completed) do
    seconds = DateTime.diff(completed, started, :second)

    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{rem(div(seconds, 60), 60)}m"
    end
  end

  defp format_duration(_, _), do: ""

  defp rail_line_style(first, last) do
    top = if first, do: "12px", else: "0"

    base =
      "left: 13px; top: #{top}; width: 2px;"

    if last do
      base <>
        " height: 16px; background: linear-gradient(180deg, var(--color-base-300), transparent);"
    else
      base <> " bottom: 0; background: var(--color-base-300);"
    end
  end

  defp rail_dot_style(color) do
    "top: 10px; left: 9px; width: 10px; height: 10px; background: #{color}; " <>
      "box-shadow: 0 0 0 4px var(--color-base-200), 0 0 0 5px var(--color-base-300);"
  end

  defp relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86_400 -> "#{div(diff, 3600)}h"
      diff < 604_800 -> "#{div(diff, 86_400)}d"
      true -> Calendar.strftime(datetime, "%b %-d")
    end
  end
end
