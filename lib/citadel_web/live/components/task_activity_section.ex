defmodule CitadelWeb.Components.TaskActivitySection do
  @moduledoc false

  use CitadelWeb, :live_component

  alias Citadel.Tasks

  import CitadelWeb.Components.TaskComponents,
    only: [user_avatar: 1, agent_run_status_classes: 1, agent_run_dot_class: 1]

  def update(%{broadcast: broadcast}, socket) do
    {:ok, handle_broadcast(broadcast, socket)}
  end

  def update(%{agent_run_updated: _broadcast}, socket) do
    {:ok, reload_agent_run_activities(socket)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns[:activities_loaded] do
        socket
      else
        activities =
          Tasks.list_task_activities!(assigns.task.id,
            actor: assigns.current_user,
            tenant: assigns.current_workspace.id,
            load: [:user, :agent_run]
          )

        socket
        |> stream(:activities, activities)
        |> assign(:activities_loaded, true)
        |> assign(:form, to_form(%{"body" => ""}, as: :comment))
        |> assign(:request_changes, false)
      end

    {:ok, socket}
  end

  defp handle_broadcast(
         %Phoenix.Socket.Broadcast{event: event, payload: %{data: activity}},
         socket
       )
       when event in ["create_comment", "create_request_changes_comment"] do
    activity =
      Ash.load!(activity, [:user],
        tenant: socket.assigns.current_workspace.id,
        actor: socket.assigns.current_user
      )

    stream_insert(socket, :activities, activity)
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

    stream_insert(socket, :activities, activity)
  end

  defp handle_broadcast(
         %Phoenix.Socket.Broadcast{event: "destroy_comment", payload: %{data: activity}},
         socket
       ) do
    stream_delete(socket, :activities, activity)
  end

  defp reload_agent_run_activities(socket) do
    activities =
      Tasks.list_task_activities!(socket.assigns.task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:user, :agent_run]
      )

    agent_run_activities = Enum.filter(activities, &(&1.type == :agent_run))

    Enum.reduce(agent_run_activities, socket, fn activity, acc ->
      stream_insert(acc, :activities, activity)
    end)
  end

  def handle_event("toggle-request-changes", _params, socket) do
    {:noreply, assign(socket, :request_changes, !socket.assigns.request_changes)}
  end

  def handle_event("submit-comment", %{"comment" => %{"body" => body}}, socket) do
    body = String.trim(body)

    if body == "" do
      {:noreply, socket}
    else
      params = %{body: body, task_id: socket.assigns.task.id}
      opts = [actor: socket.assigns.current_user, tenant: socket.assigns.current_workspace.id]

      activity =
        if socket.assigns.request_changes do
          Tasks.create_request_changes_comment!(params, opts)
        else
          Tasks.create_comment!(params, opts)
        end

      activity =
        Ash.load!(activity, [:user],
          tenant: socket.assigns.current_workspace.id,
          actor: socket.assigns.current_user
        )

      socket =
        socket
        |> stream_insert(:activities, activity)
        |> assign(:form, to_form(%{"body" => ""}, as: :comment))
        |> assign(:request_changes, false)

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

    {:noreply, stream_delete(socket, :activities, activity)}
  end

  def handle_event("request-cancel-agent-run", %{"run-id" => run_id}, socket) do
    send(self(), {:request_cancel_agent_run, run_id})
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="py-4 border-t border-base-300 max-w-5xl">
      <h2 class="text-sm font-semibold text-base-content/70 mb-4">Activity</h2>

      <div id={"#{@id}-list"} phx-update="stream" class="space-y-3 mb-6">
        <div id={"#{@id}-empty"} class="hidden only:block text-base-content/50 italic text-sm">
          No activity yet
        </div>
        <div
          :for={{dom_id, activity} <- @streams.activities}
          id={dom_id}
          class={[
            "flex gap-2 group rounded-lg p-2 -ml-2",
            activity.type == :change_request && "bg-warning/5 border-l-2 border-warning",
            activity.type == :agent_run && "bg-base-200/50 border-l-2 border-info/40"
          ]}
        >
          <div class="flex-shrink-0 pt-0.5">
            <.activity_actor_avatar activity={activity} />
          </div>
          <div class="flex-1 min-w-0">
            <%= if activity.type == :agent_run and not is_nil(activity.agent_run) do %>
              <.agent_run_activity_content
                activity={activity}
                can_edit={@can_edit}
                myself={@myself}
              />
            <% else %>
              <.comment_activity_content
                activity={activity}
                current_user={@current_user}
                myself={@myself}
              />
            <% end %>
          </div>
        </div>
      </div>

      <.form
        for={@form}
        id={"#{@id}-form"}
        phx-submit="submit-comment"
        phx-target={@myself}
        class="flex gap-2"
      >
        <div class="flex-shrink-0 pt-0.5">
          <.user_avatar user={@current_user} />
        </div>
        <div class="flex-1">
          <textarea
            name={@form[:body].name}
            value={@form[:body].value}
            rows="2"
            placeholder={
              if(@request_changes,
                do: "Describe what changes are needed...",
                else: "Add a comment..."
              )
            }
            class="textarea textarea-bordered w-full text-sm resize-none"
            id={"#{@id}-body"}
            phx-hook="CmdEnterSubmit"
          />
          <div class="flex items-center justify-between mt-2">
            <label
              class="flex items-center gap-2 cursor-pointer select-none"
              id={"#{@id}-request-changes-toggle"}
            >
              <input
                type="checkbox"
                checked={@request_changes}
                phx-click="toggle-request-changes"
                phx-target={@myself}
                class="checkbox checkbox-warning checkbox-xs"
              />
              <span class={[
                "text-xs",
                if(@request_changes, do: "text-warning font-medium", else: "text-base-content/50")
              ]}>
                Request changes
              </span>
            </label>
            <button
              type="submit"
              class={[
                "btn btn-sm",
                if(@request_changes, do: "btn-warning", else: "btn-primary")
              ]}
            >
              {if(@request_changes, do: "Request Changes", else: "Comment")}
            </button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  attr :activity, :map, required: true
  attr :current_user, :any, required: true
  attr :myself, :any, required: true

  defp comment_activity_content(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-sm font-medium text-base-content">
        <.activity_actor_name activity={@activity} />
      </span>
      <span
        :if={@activity.type == :change_request}
        class="inline-flex items-center gap-1 text-xs font-medium text-warning bg-warning/10 px-1.5 py-0.5 rounded"
      >
        <.icon name="hero-arrow-path" class="size-3" /> Changes Requested
      </span>
      <span class="text-xs text-base-content/40">
        {relative_time(@activity.inserted_at)}
      </span>
      <button
        :if={@activity.user_id == @current_user.id}
        phx-click="delete-comment"
        phx-target={@myself}
        phx-value-id={@activity.id}
        class="text-xs text-base-content/30 hover:text-error opacity-0 group-hover:opacity-100 transition-opacity"
        data-confirm="Delete this comment?"
      >
        <.icon name="hero-trash" class="size-3" />
      </button>
    </div>
    <p class="text-sm text-base-content/80 mt-1">
      {@activity.body}
    </p>
    """
  end

  attr :activity, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :myself, :any, required: true

  defp agent_run_activity_content(assigns) do
    assigns = assign(assigns, :run, assigns.activity.agent_run)

    ~H"""
    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center gap-2">
        <span class="text-sm font-medium text-base-content">
          <.activity_actor_name activity={@activity} />
        </span>
        <span class={[
          "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium",
          agent_run_status_classes(@run.status)
        ]}>
          <span class={["size-1.5 rounded-full", agent_run_dot_class(@run.status)]} />
          {@run.status}
        </span>
        <span :if={@run.error_message} class="text-xs text-error">
          {@run.error_message}
        </span>
        <.link
          :if={@run.status == :running}
          navigate={~p"/agent-runs/#{@run.id}"}
          class="btn btn-xs btn-ghost text-info hover:bg-info/10"
        >
          <.icon name="hero-eye" class="size-3.5" /> Watch
        </.link>
        <button
          :if={@can_edit and @run.status in [:pending, :running]}
          phx-click="request-cancel-agent-run"
          phx-target={@myself}
          phx-value-run-id={@run.id}
          class="btn btn-xs btn-ghost text-error hover:bg-error/10"
        >
          <.icon name="hero-x-mark" class="size-3.5" /> Cancel
        </button>
      </div>
      <div class="text-xs text-base-content/50 flex gap-3">
        <span class="text-xs text-base-content/40">
          {relative_time(@activity.inserted_at)}
        </span>
        <span :if={@run.started_at}>
          Started: {Calendar.strftime(@run.started_at, "%b %d %H:%M:%S")}
        </span>
        <span :if={@run.completed_at}>
          Completed: {Calendar.strftime(@run.completed_at, "%b %d %H:%M:%S")}
        </span>
      </div>
    </div>

    <details :if={@run.commits != nil and @run.commits != []} class="group/details">
      <summary class="text-xs font-medium text-base-content/60 cursor-pointer hover:text-base-content/80 select-none">
        Commits ({length(@run.commits)})
      </summary>
      <ul class="mt-2 space-y-1">
        <li :for={commit <- @run.commits} class="flex items-start gap-2 text-xs">
          <code class="px-1.5 py-0.5 bg-base-300/50 rounded font-mono text-base-content/70 shrink-0">
            {String.slice(commit["sha"], 0..6)}
          </code>
          <span class="text-base-content/80">{commit["message"]}</span>
        </li>
      </ul>
    </details>

    <details :if={@run.test_output && @run.test_output != ""} class="group/details mt-2">
      <summary class="text-xs font-medium text-base-content/60 cursor-pointer hover:text-base-content/80 select-none">
        Test Output
      </summary>
      <pre class="mt-2 p-3 bg-base-300/50 rounded text-xs overflow-x-auto max-h-96 overflow-y-auto"><code>{@run.test_output}</code></pre>
    </details>

    <details :if={@run.logs && @run.logs != ""} class="group/details mt-2">
      <summary class="text-xs font-medium text-base-content/60 cursor-pointer hover:text-base-content/80 select-none">
        Logs
      </summary>
      <pre class="mt-2 p-3 bg-base-300/50 rounded text-xs overflow-x-auto max-h-96 overflow-y-auto"><code>{@run.logs}</code></pre>
    </details>
    """
  end

  attr :activity, :map, required: true

  defp activity_actor_avatar(%{activity: %{actor_type: :user, user: user}} = assigns)
       when not is_nil(user) do
    assigns = assign(assigns, :user, user)

    ~H"""
    <.user_avatar user={@user} />
    """
  end

  defp activity_actor_avatar(%{activity: %{actor_type: :system}} = assigns) do
    ~H"""
    <div class="avatar avatar-placeholder">
      <div class="w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs">
        <.icon name="hero-cog-6-tooth" class="size-3.5 text-base-content/60" />
      </div>
    </div>
    """
  end

  defp activity_actor_avatar(%{activity: %{actor_type: :ai}} = assigns) do
    ~H"""
    <div class="avatar avatar-placeholder">
      <div class="w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs">
        <.icon name="hero-cpu-chip" class="size-3.5 text-base-content/60" />
      </div>
    </div>
    """
  end

  defp activity_actor_avatar(assigns) do
    ~H"""
    <div class="avatar avatar-placeholder">
      <div class="w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs">
        ?
      </div>
    </div>
    """
  end

  attr :activity, :map, required: true

  defp activity_actor_name(%{activity: %{actor_type: :user, user: user}} = assigns)
       when not is_nil(user) do
    assigns = assign(assigns, :user, user)

    ~H"""
    {to_string(@user.email)}
    """
  end

  defp activity_actor_name(%{activity: %{actor_display_name: name}} = assigns)
       when not is_nil(name) do
    assigns = assign(assigns, :name, name)

    ~H"""
    {@name}
    """
  end

  defp activity_actor_name(assigns) do
    ~H"""
    Unknown
    """
  end

  defp relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86_400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86_400)} days ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
