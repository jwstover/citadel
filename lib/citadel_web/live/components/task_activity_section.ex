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
      end

    {:ok, socket}
  end

  defp handle_broadcast(
         %Phoenix.Socket.Broadcast{event: "create_comment", payload: %{data: activity}},
         socket
       ) do
    activity = Ash.load!(activity, [:user], tenant: socket.assigns.current_workspace.id)
    stream_insert(socket, :activities, activity)
  end

  defp handle_broadcast(
         %Phoenix.Socket.Broadcast{event: "destroy_comment", payload: %{data: activity}},
         socket
       ) do
    stream_delete(socket, :activities, activity)
  end

  def handle_event("submit-comment", %{"body" => body}, socket) do
    body = String.trim(body)

    if body == "" do
      {:noreply, socket}
    else
      activity =
        Tasks.create_comment!(
          %{body: body, task_id: socket.assigns.task.id},
          actor: socket.assigns.current_user,
          tenant: socket.assigns.current_workspace.id
        )

      activity = Ash.load!(activity, [:user], tenant: socket.assigns.current_workspace.id)

      {:noreply, stream_insert(socket, :activities, activity)}
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
          class="flex gap-2 group"
        >
          <div class="flex-shrink-0 pt-0.5">
            <.activity_actor_avatar activity={activity} />
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium text-base-content">
                <.activity_actor_name activity={activity} />
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
            </div>
            <p class="text-sm text-base-content/80 mt-1">
              {activity.body}
            </p>
          </div>
        </div>
      </div>

      <form id={"#{@id}-form"} phx-submit="submit-comment" phx-target={@myself} class="flex gap-2">
        <div class="flex-shrink-0 pt-0.5">
          <.user_avatar user={@current_user} />
        </div>
        <div class="flex-1">
          <textarea
            name="body"
            rows="2"
            placeholder="Add a comment..."
            class="textarea textarea-bordered w-full text-sm resize-none"
            phx-hook="ClearOnSubmit"
            id={"#{@id}-body"}
          />
          <div class="flex justify-end mt-2">
            <button type="submit" class="btn btn-sm btn-primary">
              Comment
            </button>
          </div>
        </div>
      </form>
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
