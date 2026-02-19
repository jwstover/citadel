defmodule CitadelWeb.Components.TasksListComponent do
  @moduledoc false

  use CitadelWeb, :live_component

  alias Citadel.Tasks

  import CitadelWeb.Components.TaskComponents, only: [task_row: 1]

  def update(%{deleted_task: %{id: task_id, task_state_id: task_state_id}}, socket) do
    old_count = Map.get(socket.assigns.tasks_by_state_count, task_state_id, 1)
    task_state_map = Map.delete(socket.assigns.task_state_map, task_id)

    socket =
      socket
      |> stream_delete_by_dom_id(stream_name(task_state_id), dom_id(task_state_id, task_id))
      |> assign(
        :tasks_by_state_count,
        Map.put(socket.assigns.tasks_by_state_count, task_state_id, max(old_count - 1, 0))
      )
      |> assign(:task_state_map, task_state_map)

    {:ok, socket}
  end

  def update(%{updated_task: task}, socket) do
    task = ensure_loaded(task, socket)
    old_state_id = Map.get(socket.assigns.task_state_map, task.id)

    socket =
      cond do
        is_nil(old_state_id) ->
          new_count = Map.get(socket.assigns.tasks_by_state_count, task.task_state_id, 0)
          task_state_map = Map.put(socket.assigns.task_state_map, task.id, task.task_state_id)

          socket
          |> stream_insert(stream_name(task.task_state_id), task)
          |> assign(
            :tasks_by_state_count,
            Map.put(socket.assigns.tasks_by_state_count, task.task_state_id, new_count + 1)
          )
          |> assign(:task_state_map, task_state_map)

        old_state_id != task.task_state_id ->
          old_count = Map.get(socket.assigns.tasks_by_state_count, old_state_id, 1)
          new_count = Map.get(socket.assigns.tasks_by_state_count, task.task_state_id, 0)
          task_state_map = Map.put(socket.assigns.task_state_map, task.id, task.task_state_id)

          updated_counts =
            socket.assigns.tasks_by_state_count
            |> Map.put(old_state_id, max(old_count - 1, 0))
            |> Map.put(task.task_state_id, new_count + 1)

          socket
          |> stream_delete_by_dom_id(stream_name(old_state_id), dom_id(old_state_id, task.id))
          |> stream_insert(stream_name(task.task_state_id), task)
          |> assign(:tasks_by_state_count, updated_counts)
          |> assign(:task_state_map, task_state_map)

        true ->
          stream_insert(socket, stream_name(task.task_state_id), task)
      end

    {:ok, socket}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:mode, fn ->
        if Map.has_key?(assigns, :tasks), do: :prop_driven, else: :self_managed
      end)
      |> load_task_states()
      |> maybe_load_tasks()
      |> init_streams()

    {:ok, socket}
  end

  @required_loads [:task_state, :assignees, :overdue?]

  defp ensure_loaded(%{__struct__: Citadel.Tasks.Task} = task, socket) do
    loads_needed =
      Enum.filter(@required_loads, fn field ->
        match?(%Ash.NotLoaded{}, Map.get(task, field))
      end)

    if loads_needed == [] do
      task
    else
      Ash.load!(task, loads_needed,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )
    end
  end

  defp ensure_loaded(%{id: id}, socket) do
    Tasks.get_task!(id,
      actor: socket.assigns.current_user,
      tenant: socket.assigns.current_workspace.id,
      load: @required_loads
    )
  end

  def handle_event("task-moved", %{"task_id" => task_id, "new_state_id" => new_state_id}, socket) do
    # Get the task before update to know old state
    task =
      Tasks.get_task!(task_id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:task_state, :assignees, :overdue?]
      )

    old_state_id = task.task_state_id

    # Update in database
    updated_task =
      Tasks.update_task!(task_id, %{task_state_id: new_state_id},
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    updated_task =
      Ash.load!(updated_task, [:task_state, :assignees, :overdue?],
        tenant: socket.assigns.current_workspace.id
      )

    # Update streams - delete from old state, insert into new state
    old_count = Map.get(socket.assigns.tasks_by_state_count, old_state_id, 1)
    new_count = Map.get(socket.assigns.tasks_by_state_count, new_state_id, 0)

    updated_counts =
      socket.assigns.tasks_by_state_count
      |> Map.put(old_state_id, old_count - 1)
      |> Map.put(new_state_id, new_count + 1)

    task_state_map = Map.put(socket.assigns.task_state_map, task_id, new_state_id)

    socket =
      socket
      |> stream_delete(stream_name(old_state_id), task)
      |> stream_insert(stream_name(new_state_id), updated_task)
      |> assign(:tasks_by_state_count, updated_counts)
      |> assign(:task_state_map, task_state_map)

    # Notify parent in prop_driven mode
    if socket.assigns.mode == :prop_driven do
      send(self(), {:tasks_list_task_moved, socket.assigns.id})
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

  defp init_streams(socket) do
    tasks = socket.assigns.tasks || []
    task_states = socket.assigns.task_states
    tasks_by_state = Enum.group_by(tasks, & &1.task_state_id)

    # Track counts separately (streams aren't enumerable)
    counts = Map.new(tasks_by_state, fn {k, v} -> {k, length(v)} end)

    # Track task_id -> state_id mapping for efficient lookups during remote updates
    task_state_map = Map.new(tasks, fn task -> {task.id, task.task_state_id} end)

    socket =
      socket
      |> assign(:tasks_by_state_count, counts)
      |> assign(:task_state_map, task_state_map)

    # Initialize a stream for each task state
    Enum.reduce(task_states, socket, fn state, acc ->
      state_tasks = Map.get(tasks_by_state, state.id, [])
      stream(acc, stream_name(state.id), state_tasks, reset: true)
    end)
  end

  # sobelow_skip ["DOS.BinToAtom"]
  defp stream_name(state_id), do: :"tasks_#{state_id}"

  defp dom_id(state_id, task_id), do: "tasks_#{state_id}-#{task_id}"

  def render(assigns) do
    ~H"""
    <table class="w-full" phx-hook="TaskDragDrop" id={@id} phx-target={@myself}>
      <%= for state <- @task_states, (@tasks_by_state_count[state.id] || 0) > 0 do %>
        <thead class="[&:not(:first-child)]:border-t [&:not(:first-child)]:border-border">
          <tr class="sticky top-0 bg-base-200 z-100">
            <td colspan="7" class="px-6 py-4">
              <div class="flex items-center justify-between">
                <h2 class="text-lg font-semibold text-base-content">
                  {state.name}
                </h2>
                <span class="badge badge-neutral badge-sm">
                  {@tasks_by_state_count[state.id] || 0}
                </span>
              </div>
            </td>
          </tr>
          <tr class="sticky top-[60px] bg-base-200 z-100">
            <th></th>
            <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 px-2"></th>
            <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left px-2">
              ID
            </th>
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
        </thead>
        <tbody
          id={"#{@id}-state-#{state.id}"}
          phx-update="stream"
          data-dropzone
          data-state-id={state.id}
        >
          <.task_row
            :for={{dom_id, task} <- @streams[stream_name(state.id)] || []}
            id={dom_id}
            task={task}
            current_user={@current_user}
            current_workspace={@current_workspace}
          />
        </tbody>
      <% end %>
    </table>
    """
  end
end
