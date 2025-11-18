defmodule CitadelWeb.HomeLive.Index do
  @moduledoc false

  use CitadelWeb, :live_view

  import CitadelWeb.Components.TaskComponents

  alias Citadel.Tasks

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
  on_mount {CitadelWeb.LiveUserAuth, :load_workspace}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Load task states ordered by their order field
      task_states = Tasks.list_task_states!(query: [sort: [order: :asc]])

      socket =
        socket
        |> assign(:task_states, task_states)
        |> assign_tasks()
        |> assign(:show_task_form, false)

      {:ok, socket}
    else
      {:ok, assign(socket, task_states: [], tasks_by_state: %{}, show_task_form: false)}
    end
  end

  def handle_event("new-task", _params, socket) do
    {:noreply, socket |> assign(:show_task_form, true)}
  end

  def handle_event("close-new-task-form", _params, socket) do
    {:noreply, socket |> assign(:show_task_form, false)}
  end

  def handle_event("task-moved", %{"task_id" => task_id, "new_state_id" => new_state_id}, socket) do
    Tasks.update_task!(task_id, %{task_state_id: new_state_id},
      actor: socket.assigns.current_user,
      tenant: socket.assigns.current_workspace.id
    )

    {:noreply, assign_tasks(socket)}
  end

  def handle_info({:task_created, _task}, socket) do
    {:noreply, assign_tasks(socket) |> assign(:show_task_form, false)}
  end

  defp assign_tasks(socket) do
    tasks =
      Tasks.list_tasks!(
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:task_state]
      )

    tasks_by_state = Enum.group_by(tasks, & &1.task_state_id)

    assign(socket, :tasks_by_state, tasks_by_state)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.control_bar />

      <.tasks_list task_states={@task_states} tasks_by_state={@tasks_by_state} />

      <.live_component
        :if={@show_task_form}
        module={CitadelWeb.Components.NewTaskModal}
        id="new-task-modal"
        current_user={@current_user}
        current_workspace={@current_workspace}
      />
    </Layouts.app>
    """
  end
end
