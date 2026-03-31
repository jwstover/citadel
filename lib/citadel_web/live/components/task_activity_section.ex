defmodule CitadelWeb.Components.TaskActivitySection do
  @moduledoc false

  use CitadelWeb, :live_component

  alias Citadel.Tasks

  import CitadelWeb.Components.TaskComponents, only: [user_avatar: 1]

  def update(%{broadcast: broadcast}, socket) do
    {:ok, handle_broadcast(broadcast, socket)}
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
            load: [:user]
          )

        socket
        |> stream(:activities, activities)
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

    stream_insert(socket, :activities, activity)
  end

  defp handle_broadcast(
         %Phoenix.Socket.Broadcast{event: "destroy_comment", payload: %{data: activity}},
         socket
       ) do
    stream_delete(socket, :activities, activity)
  end

  def handle_event("toggle-request-changes", _params, socket) do
    {:noreply, assign(socket, :request_changes, !socket.assigns.request_changes)}
  end

  def handle_event("toggle-reply", %{"id" => id}, socket) do
    reply_to =
      if socket.assigns.reply_to_activity_id == id do
        nil
      else
        id
      end

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
            params = %{
              body: body,
              task_id: socket.assigns.task.id,
              parent_activity_id: socket.assigns.reply_to_activity_id
            }

            Tasks.create_question_response!(params, opts)

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
        |> stream_insert(:activities, activity)
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

    {:noreply, stream_delete(socket, :activities, activity)}
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
            activity.type == :question && "bg-purple-500/5 border-l-2 border-purple-400",
            activity.type == :question_response && "ml-8 bg-base-200/50 rounded-lg"
          ]}
        >
          <div class="flex-shrink-0 pt-0.5">
            <.activity_actor_avatar activity={activity} />
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium text-base-content">
                <.activity_actor_name activity={activity} />
              </span>
              <span
                :if={activity.type == :change_request}
                class="inline-flex items-center gap-1 text-xs font-medium text-warning bg-warning/10 px-1.5 py-0.5 rounded"
              >
                <.icon name="hero-arrow-path" class="size-3" /> Changes Requested
              </span>
              <span
                :if={activity.type == :question}
                class="inline-flex items-center gap-1 text-xs font-medium text-purple-400 bg-purple-500/10 px-1.5 py-0.5 rounded"
              >
                <.icon name="hero-question-mark-circle" class="size-3" /> Agent Question
              </span>
              <span
                :if={activity.type == :question_response}
                class="inline-flex items-center gap-1 text-xs font-medium text-base-content/50 bg-base-200 px-1.5 py-0.5 rounded"
              >
                In Reply
              </span>
              <span class="text-xs text-base-content/40">
                {relative_time(activity.inserted_at)}
              </span>
              <button
                :if={activity.user_id == @current_user.id}
                phx-click="delete-comment"
                phx-target={@myself}
                phx-value-id={activity.id}
                class="text-xs text-base-content/30 hover:text-error opacity-0 group-hover:opacity-100 transition-opacity"
                data-confirm="Delete this comment?"
              >
                <.icon name="hero-trash" class="size-3" />
              </button>
              <button
                :if={activity.type == :question}
                phx-click="toggle-reply"
                phx-target={@myself}
                phx-value-id={activity.id}
                class="text-xs text-purple-400 hover:text-purple-300 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <.icon name="hero-chat-bubble-left" class="size-3" /> Reply
              </button>
            </div>
            <p class="text-sm text-base-content/80 mt-1">
              {activity.body}
            </p>
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
          <div
            :if={@reply_to_activity_id}
            class="flex items-center justify-between bg-purple-500/10 text-purple-400 text-xs px-3 py-1.5 rounded-t-lg border border-b-0 border-purple-400/20"
          >
            <span>Replying to agent question</span>
            <button
              type="button"
              phx-click="toggle-reply"
              phx-target={@myself}
              phx-value-id={@reply_to_activity_id}
              class="hover:text-purple-300"
            >
              <.icon name="hero-x-mark" class="size-3.5" />
            </button>
          </div>
          <textarea
            name={@form[:body].name}
            value={@form[:body].value}
            rows="2"
            placeholder={
              cond do
                @reply_to_activity_id -> "Type your reply to the agent's question..."
                @request_changes -> "Describe what changes are needed..."
                true -> "Add a comment..."
              end
            }
            class={[
              "textarea textarea-bordered w-full text-sm resize-none",
              @reply_to_activity_id && "rounded-t-none"
            ]}
            id={"#{@id}-body"}
            phx-hook="CmdEnterSubmit"
          />
          <div class="flex items-center justify-between mt-2">
            <label
              :if={!@reply_to_activity_id}
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
            <div :if={@reply_to_activity_id} />
            <button
              type="submit"
              class={[
                "btn btn-sm",
                cond do
                  @reply_to_activity_id -> "btn-primary"
                  @request_changes -> "btn-warning"
                  true -> "btn-primary"
                end
              ]}
            >
              {cond do
                @reply_to_activity_id -> "Reply"
                @request_changes -> "Request Changes"
                true -> "Comment"
              end}
            </button>
          </div>
        </div>
      </.form>
    </div>
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
