defmodule CitadelWeb.Components.TasksListComponent do
  @moduledoc false

  use CitadelWeb, :live_component

  alias Citadel.Tasks

  import CitadelWeb.Components.TaskComponents, only: [task_row: 1]

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:mode, fn ->
        if Map.has_key?(assigns, :tasks), do: :prop_driven, else: :self_managed
      end)
      |> load_task_states()
      |> maybe_load_tasks()
      |> group_tasks()

    {:ok, socket}
  end

  def handle_event("task-moved", %{"task_id" => task_id, "new_state_id" => new_state_id}, socket) do
    Tasks.update_task!(task_id, %{task_state_id: new_state_id},
      actor: socket.assigns.current_user,
      tenant: socket.assigns.current_workspace.id
    )

    socket =
      case socket.assigns.mode do
        :self_managed ->
          socket |> maybe_load_tasks() |> group_tasks()

        :prop_driven ->
          send(self(), {:tasks_list_task_moved, socket.assigns.id})
          socket
      end

    {:noreply, socket}
  end

  defp load_task_states(socket) do
    task_states = Tasks.list_task_states!(query: [sort: [order: :asc]])
    assign(socket, :task_states, task_states)
  end

  defp maybe_load_tasks(%{assigns: %{mode: :self_managed}} = socket) do
    tasks =
      Tasks.list_top_level_tasks!(
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:task_state, :assignees, :overdue?]
      )

    assign(socket, :tasks, tasks)
  end

  defp maybe_load_tasks(socket), do: socket

  defp group_tasks(socket) do
    tasks_by_state = Enum.group_by(socket.assigns.tasks || [], & &1.task_state_id)
    assign(socket, :tasks_by_state, tasks_by_state)
  end

  def render(assigns) do
    ~H"""
    <table class="w-full" phx-hook="TaskDragDrop" id={@id} phx-target={@myself}>
      <tbody
        :for={state <- @task_states}
        data-dropzone
        data-state-id={state.id}
        class="[&:not(:first-child)]:border-t [&:not(:first-child)]:border-border"
      >
        <tr class="sticky top-0 bg-base-200 z-100">
          <td colspan="7" class="px-6 py-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-base-content">
                {state.name}
              </h2>
              <span class="badge badge-neutral badge-sm">
                {length(Map.get(@tasks_by_state, state.id, []))}
              </span>
            </div>
          </td>
        </tr>
        <tr class="sticky top-[60px] bg-base-200 z-100">
          <th></th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 px-2"></th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left px-2">ID</th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left">Name</th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left px-2">
            Priority
          </th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left px-2">
            Due Date
          </th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left px-2">
            Assignee
          </th>
        </tr>
        <%= if tasks = Map.get(@tasks_by_state, state.id) do %>
          <.task_row
            :for={task <- tasks}
            task={task}
            current_user={@current_user}
            current_workspace={@current_workspace}
          />
        <% end %>
      </tbody>
    </table>
    """
  end
end
