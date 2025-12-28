defmodule CitadelWeb.DashboardLive.Index do
  @moduledoc false

  use CitadelWeb, :live_view

  import CitadelWeb.Components.TaskComponents, only: [control_bar: 1]

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
  on_mount {CitadelWeb.LiveUserAuth, :load_workspace}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      CitadelWeb.Endpoint.subscribe("tasks:tasks:#{socket.assigns.current_workspace.id}")
    end

    {:ok, assign(socket, :show_task_form, false)}
  end

  def handle_event("new-task", _params, socket) do
    {:noreply, assign(socket, :show_task_form, true)}
  end

  def handle_event("close-new-task-form", _params, socket) do
    {:noreply, assign(socket, :show_task_form, false)}
  end

  def handle_info({:task_created, _task}, socket) do
    send_update(CitadelWeb.Components.TasksListComponent, id: "tasks-container")
    {:noreply, assign(socket, :show_task_form, false)}
  end

  def handle_info({:task_state_changed, _task}, socket) do
    send_update(CitadelWeb.Components.TasksListComponent, id: "tasks-container")
    {:noreply, socket}
  end

  def handle_info({:task_priority_changed, _task}, socket) do
    send_update(CitadelWeb.Components.TasksListComponent, id: "tasks-container")
    {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: "tasks:tasks:" <> _, payload: payload}, socket) do
    case payload do
      %{action: :destroy} ->
        send_update(CitadelWeb.Components.TasksListComponent,
          id: "tasks-container",
          deleted_task: payload
        )

      %{parent_task_id: parent_id} when not is_nil(parent_id) ->
        # Ignore sub-tasks - they're not shown in the main task list
        :ok

      task ->
        send_update(CitadelWeb.Components.TasksListComponent,
          id: "tasks-container",
          updated_task: task
        )
    end

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_workspace={@current_workspace} workspaces={@workspaces}>
      <div class="relative h-full overflow-hidden card bg-base-200 border border-base-300">
        <.control_bar />

        <div class="h-full overflow-auto">
          <.live_component
            module={CitadelWeb.Components.TasksListComponent}
            id="tasks-container"
            current_user={@current_user}
            current_workspace={@current_workspace}
          />
        </div>

        <.live_component
          :if={@show_task_form}
          module={CitadelWeb.Components.NewTaskModal}
          id="new-task-modal"
          current_user={@current_user}
          current_workspace={@current_workspace}
        />
      </div>
    </Layouts.app>
    """
  end
end
