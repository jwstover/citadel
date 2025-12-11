defmodule CitadelWeb.Components.PriorityDropdown do
  @moduledoc false

  use CitadelWeb, :live_component

  alias Citadel.Tasks

  import CitadelWeb.Components.TaskComponents, only: [priority_badge: 1]

  @priorities [:low, :medium, :high, :urgent]

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:priorities, @priorities)
     |> assign_new(:align_right, fn -> false end)}
  end

  def handle_event("change-priority", %{"priority" => priority}, socket) do
    priority_atom = String.to_existing_atom(priority)

    Tasks.update_task!(socket.assigns.task.id, %{priority: priority_atom},
      actor: socket.assigns.current_user,
      tenant: socket.assigns.current_workspace.id
    )

    task = %{socket.assigns.task | priority: priority_atom}

    send(self(), {:task_priority_changed, task})

    {:noreply, assign(socket, :task, task)}
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class={["dropdown", @align_right && "dropdown-end"]}>
      <div tabindex="0" role="button" class="cursor-pointer">
        <.priority_badge priority={@task.priority} />
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-200 border border-base-content/20 rounded-box z-50 w-32 p-2 shadow-lg"
      >
        <li :for={priority <- @priorities}>
          <button
            phx-click="change-priority"
            phx-target={@myself}
            phx-value-priority={priority}
            class={[
              "flex items-center gap-2",
              priority == @task.priority && "active"
            ]}
          >
            <.priority_badge priority={priority} />
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
