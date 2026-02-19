defmodule CitadelWeb.Components.TaskStateDropdown do
  @moduledoc false

  use CitadelWeb, :live_component

  alias Citadel.Tasks

  import CitadelWeb.Components.TaskComponents, only: [task_state_icon: 1]

  def update_many(assigns_sockets) do
    task_states = Tasks.list_task_states!(query: [sort: [order: :asc]])

    Enum.map(assigns_sockets, fn {assigns, socket} ->
      # Load blocked? and blocking_count if not already loaded
      task =
        case assigns.task.blocked? do
          %Ash.NotLoaded{} ->
            Ash.load!(assigns.task, [:blocked?, :blocking_count],
              actor: assigns[:current_user],
              tenant: assigns[:current_workspace].id
            )

          _ ->
            assigns.task
        end

      socket
      |> assign(assigns)
      |> assign(:task, task)
      |> assign(:task_states, task_states)
      |> assign(:show_completion_warning, false)
      |> assign(:pending_state_id, nil)
    end)
  end

  def handle_event("change-state", %{"state-id" => state_id}, socket) do
    new_state = Enum.find(socket.assigns.task_states, &(&1.id == state_id))

    # Check if completing a blocked task
    if new_state.is_complete and socket.assigns.task.blocked? do
      {:noreply,
       socket
       |> assign(:show_completion_warning, true)
       |> assign(:pending_state_id, state_id)}
    else
      complete_state_change(socket, state_id)
    end
  end

  def handle_event("confirm-complete", _params, socket) do
    complete_state_change(socket, socket.assigns.pending_state_id)
  end

  def handle_event("cancel-complete", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_completion_warning, false)
     |> assign(:pending_state_id, nil)}
  end

  defp complete_state_change(socket, state_id) do
    updated_task =
      Tasks.update_task!(socket.assigns.task.id, %{task_state_id: state_id},
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    task =
      Ash.load!(updated_task, [:task_state],
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    send(self(), {:task_state_changed, task})

    {:noreply,
     socket
     |> assign(:task, task)
     |> assign(:show_completion_warning, false)
     |> assign(:pending_state_id, nil)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <div id={@id} class="dropdown">
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

      <.live_component
        :if={@show_completion_warning}
        module={CitadelWeb.Components.ConfirmationModal}
        id={"#{@id}-completion-warning"}
        title="Incomplete Dependencies"
        message={
          "This task depends on #{@task.blocking_count} incomplete task(s). Are you sure you want to mark it as complete?"
        }
        confirm_label="Complete Anyway"
        cancel_label="Cancel"
        on_confirm="confirm-complete"
        on_cancel="cancel-complete"
        target={@myself}
      />
    </div>
    """
  end
end
