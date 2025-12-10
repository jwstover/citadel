defmodule CitadelWeb.Components.AssigneeSelect do
  @moduledoc false

  use CitadelWeb, :live_component

  import CitadelWeb.Components.TaskComponents, only: [user_avatar: 1]

  def update(assigns, socket) do
    workspace =
      Ash.load!(assigns.workspace, [:members, :owner], actor: assigns.current_user)

    members =
      [workspace.owner | workspace.members]
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(fn m -> m.name || to_string(m.email) end)

    selected = MapSet.new(assigns[:selected_ids] || [])

    socket =
      socket
      |> assign(assigns)
      |> assign(:members, members)
      |> assign(:selected, selected)
      |> assign(:search, "")
      |> assign(:open, false)

    {:ok, socket}
  end

  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :open, !socket.assigns.open)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :open, false)}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, assign(socket, :search, search)}
  end

  def handle_event("toggle-member", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected, id) do
        MapSet.delete(socket.assigns.selected, id)
      else
        MapSet.put(socket.assigns.selected, id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  defp filtered_members(members, search) do
    search = String.downcase(search)

    if search == "" do
      members
    else
      Enum.filter(members, fn member ->
        String.contains?(String.downcase(member.name || ""), search) ||
          String.contains?(String.downcase(to_string(member.email)), search)
      end)
    end
  end

  defp selected_members(members, selected) do
    Enum.filter(members, fn member -> MapSet.member?(selected, member.id) end)
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:filtered_members, filtered_members(assigns.members, assigns.search))
      |> assign(:selected_members, selected_members(assigns.members, assigns.selected))

    ~H"""
    <div class="relative" phx-click-away="close" phx-target={@myself}>
      <input
        :for={id <- @selected}
        type="hidden"
        name={@field_name}
        value={id}
      />

      <div
        class="flex items-center gap-2 cursor-pointer px-3 py-2 border border-base-content/20 rounded-lg bg-base-100 hover:border-base-content/40 transition-colors"
        phx-click="toggle"
        phx-target={@myself}
      >
        <%= if Enum.empty?(@selected_members) do %>
          <span class="text-base-content/50">Select assignees...</span>
        <% else %>
          <div class="flex items-center gap-1 flex-wrap">
            <div
              :for={member <- Enum.take(@selected_members, 3)}
              class="flex items-center gap-1 bg-base-200 rounded-full px-2 py-0.5 text-sm"
            >
              <.user_avatar user={member} size="w-4 h-4" text_size="text-[10px]" />
              <span class="truncate max-w-20">{member.name || member.email}</span>
            </div>
            <span :if={length(@selected_members) > 3} class="text-sm text-base-content/70">
              +{length(@selected_members) - 3} more
            </span>
          </div>
        <% end %>
        <.icon
          name="hero-chevron-down"
          class={
            if @open,
              do: "size-4 ml-auto transition-transform rotate-180",
              else: "size-4 ml-auto transition-transform"
          }
        />
      </div>

      <div
        :if={@open}
        class="absolute z-50 mt-1 w-full bg-base-200 border border-base-content/20 rounded-lg shadow-lg overflow-hidden"
      >
        <div class="p-2 border-b border-base-content/10">
          <input
            type="text"
            value={@search}
            placeholder="Search members..."
            class="w-full input input-sm bg-base-100"
            phx-keyup="search"
            phx-target={@myself}
            phx-debounce="150"
          />
        </div>

        <div class="max-h-48 overflow-y-auto">
          <%= if Enum.empty?(@filtered_members) do %>
            <div class="p-3 text-center text-base-content/50 text-sm">
              No members found
            </div>
          <% else %>
            <button
              :for={member <- @filtered_members}
              type="button"
              class={[
                "w-full flex items-center gap-3 px-3 py-2 hover:bg-base-300 transition-colors text-left",
                MapSet.member?(@selected, member.id) && "bg-base-300"
              ]}
              phx-click="toggle-member"
              phx-target={@myself}
              phx-value-id={member.id}
            >
              <input
                type="checkbox"
                class="checkbox checkbox-sm"
                checked={MapSet.member?(@selected, member.id)}
                tabindex="-1"
              />
              <.user_avatar user={member} />
              <div class="flex-1 min-w-0">
                <div class="font-medium truncate">{member.name || member.email}</div>
                <div :if={member.name} class="text-xs text-base-content/60 truncate">
                  {member.email}
                </div>
              </div>
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
