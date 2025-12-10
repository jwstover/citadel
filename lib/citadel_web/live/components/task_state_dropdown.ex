defmodule CitadelWeb.Components.TaskStateDropdown do
  @moduledoc false

  use CitadelWeb, :live_component

  alias Citadel.Tasks

  import CitadelWeb.Components.TaskComponents, only: [task_state_icon: 1]

  def update(assigns, socket) do
    task_states = Tasks.list_task_states!(query: [sort: [order: :asc]])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:task_states, task_states)}
  end

  def handle_event("change-state", %{"state-id" => state_id}, socket) do
    Tasks.update_task!(socket.assigns.task.id, %{task_state_id: state_id},
      actor: socket.assigns.current_user,
      tenant: socket.assigns.current_workspace.id
    )

    task =
      Ash.load!(socket.assigns.task, [:task_state],
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    send(self(), {:task_state_changed, task})

    {:noreply, assign(socket, :task, task)}
  end

  def render(assigns) do
    ~H"""
    <div class="dropdown">
      <div tabindex="0" role="button" class="cursor-pointer">
        <.task_state_icon task_state={@task.task_state} size={@size} />
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-300 border border-base-content/20 rounded-box z-50 w-48 p-2 shadow-lg"
      >
        <li :for={state <- @task_states}>
          <button
            phx-click="change-state"
            phx-target={@myself}
            phx-value-state-id={state.id}
            class={[
              "flex items-center gap-2",
              state.id == @task.task_state_id && "active"
            ]}
          >
            <.task_state_icon task_state={state} size="size-4" />
            <span>{state.name}</span>
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
