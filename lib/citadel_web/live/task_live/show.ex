defmodule CitadelWeb.TaskLive.Show do
  @moduledoc false

  use CitadelWeb, :live_view

  alias Citadel.Tasks

  import CitadelWeb.Components.TaskComponents,
    only: [task_state_icon: 1, user_avatar: 1, priority_badge: 1]

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
  on_mount {CitadelWeb.LiveUserAuth, :load_workspace}

  def mount(%{"id" => id}, _session, socket) do
    task =
      Tasks.get_task_by_human_id!(id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [
          :task_state,
          :user,
          :parent_task,
          :ancestors,
          :assignees,
          :overdue?,
          :blocked?,
          :blocking_count,
          dependencies: [:task_state],
          dependents: [:task_state]
        ]
      )

    sub_tasks =
      Tasks.list_sub_tasks!(task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:task_state, :assignees, :overdue?]
      )

    task_dependencies =
      Tasks.list_task_dependencies!(task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    can_edit = Ash.can?({task, :update}, socket.assigns.current_user)
    can_delete = Ash.can?({task, :destroy}, socket.assigns.current_user)

    if connected?(socket) do
      CitadelWeb.Endpoint.subscribe("tasks:task:#{task.id}")
      CitadelWeb.Endpoint.subscribe("tasks:task_children:#{task.id}")
      CitadelWeb.Endpoint.subscribe("tasks:task_dependencies:#{task.id}")
      CitadelWeb.Endpoint.subscribe("tasks:task_dependents:#{task.id}")
    end

    socket =
      socket
      |> assign(:task, task)
      |> assign(:sub_tasks, sub_tasks)
      |> assign(:sub_tasks_count, length(sub_tasks))
      |> assign(:task_dependencies, task_dependencies)
      |> assign(:can_edit, can_edit)
      |> assign(:can_delete, can_delete)
      |> assign(:show_sub_task_form, false)
      |> assign(:confirm_delete, false)

    {:ok, socket}
  end

  def handle_event("new-sub-task", _params, socket) do
    {:noreply, assign(socket, :show_sub_task_form, true)}
  end

  def handle_event("close-sub-task-form", _params, socket) do
    {:noreply, assign(socket, :show_sub_task_form, false)}
  end

  def handle_event("confirm_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("delete", _params, socket) do
    task = socket.assigns.task
    parent_task = task.parent_task

    case Tasks.destroy_task(task, actor: socket.assigns.current_user) do
      :ok ->
        redirect_path = if parent_task, do: ~p"/tasks/#{parent_task.human_id}", else: ~p"/"

        {:noreply,
         socket
         |> put_flash(:info, "Task deleted successfully")
         |> push_navigate(to: redirect_path)}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:confirm_delete, false)
         |> put_flash(:error, "Failed to delete task")}
    end
  end

  def handle_event("add-dependency", %{"human_id" => human_id}, socket) do
    human_id = String.trim(human_id)

    if human_id == "" do
      {:noreply, socket}
    else
      handle_add_dependency(human_id, socket)
    end
  end

  def handle_event("remove-dependency", %{"id" => dependency_id}, socket) do
    case Tasks.destroy_task_dependency(dependency_id,
           actor: socket.assigns.current_user,
           tenant: socket.assigns.current_workspace.id
         ) do
      :ok ->
        {task, task_dependencies} = reload_task_with_dependencies(socket)

        {:noreply,
         socket
         |> assign(:task, task)
         |> assign(:task_dependencies, task_dependencies)
         |> put_flash(:info, "Dependency removed successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove dependency")}
    end
  end

  def handle_event("save-description", %{"content" => content}, socket) do
    case Tasks.update_task(socket.assigns.task.id, %{description: content},
           actor: socket.assigns.current_user,
           tenant: socket.assigns.current_workspace.id
         ) do
      {:ok, task} ->
        task =
          Ash.load!(
            task,
            [
              :task_state,
              :user,
              :parent_task,
              :ancestors,
              :assignees,
              :overdue?
            ],
            tenant: socket.assigns.current_workspace.id
          )

        {:noreply, assign(socket, :task, task)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save description")}
    end
  end

  def handle_event("save-title", %{"value" => title}, socket) do
    title = String.trim(title)

    if title == "" or title == socket.assigns.task.title do
      {:noreply, socket}
    else
      case Tasks.update_task(socket.assigns.task.id, %{title: title},
             actor: socket.assigns.current_user,
             tenant: socket.assigns.current_workspace.id
           ) do
        {:ok, task} ->
          task =
            Ash.load!(
              task,
              [
                :task_state,
                :user,
                :parent_task,
                :ancestors,
                :assignees,
                :overdue?
              ],
              tenant: socket.assigns.current_workspace.id
            )

          {:noreply, assign(socket, :task, task)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to save title")}
      end
    end
  end

  def handle_event("save-due-date", %{"value" => due_date}, socket) do
    due_date = if due_date == "", do: nil, else: Date.from_iso8601!(due_date)

    if due_date == socket.assigns.task.due_date do
      {:noreply, socket}
    else
      case Tasks.update_task(socket.assigns.task.id, %{due_date: due_date},
             actor: socket.assigns.current_user,
             tenant: socket.assigns.current_workspace.id
           ) do
        {:ok, task} ->
          task =
            Ash.load!(
              task,
              [
                :task_state,
                :user,
                :parent_task,
                :ancestors,
                :assignees,
                :overdue?
              ],
              tenant: socket.assigns.current_workspace.id
            )

          {:noreply, assign(socket, :task, task)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to save due date")}
      end
    end
  end

  def handle_info({:task_created, _sub_task}, socket) do
    sub_tasks =
      Tasks.list_sub_tasks!(socket.assigns.task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:task_state, :assignees, :overdue?]
      )

    send_update(CitadelWeb.Components.TasksListComponent,
      id: "sub-tasks-#{socket.assigns.task.id}",
      tasks: sub_tasks
    )

    socket =
      socket
      |> assign(:sub_tasks, sub_tasks)
      |> assign(:sub_tasks_count, length(sub_tasks))
      |> assign(:show_sub_task_form, false)
      |> put_flash(:info, "Sub-task created successfully")

    {:noreply, socket}
  end

  def handle_info({:task_priority_changed, task}, socket) do
    updated_task = %{socket.assigns.task | priority: task.priority}
    {:noreply, assign(socket, :task, updated_task)}
  end

  def handle_info({:assignees_changed, assignee_ids}, socket) do
    case Tasks.update_task(socket.assigns.task.id, %{assignees: assignee_ids},
           actor: socket.assigns.current_user,
           tenant: socket.assigns.current_workspace.id
         ) do
      {:ok, task} ->
        task =
          Ash.load!(
            task,
            [
              :task_state,
              :user,
              :parent_task,
              :ancestors,
              :assignees,
              :overdue?
            ],
            tenant: socket.assigns.current_workspace.id
          )

        {:noreply, assign(socket, :task, task)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update assignees")}
    end
  end

  def handle_info({:task_state_changed, _task}, socket) do
    task =
      Ash.load!(
        socket.assigns.task,
        [
          :task_state,
          :user,
          :parent_task,
          :ancestors,
          :assignees,
          :overdue?
        ],
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    sub_tasks =
      Tasks.list_sub_tasks!(task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:task_state, :assignees, :overdue?]
      )

    send_update(CitadelWeb.Components.TasksListComponent,
      id: "sub-tasks-#{task.id}",
      tasks: sub_tasks
    )

    socket =
      socket
      |> assign(:task, task)
      |> assign(:sub_tasks, sub_tasks)
      |> assign(:sub_tasks_count, length(sub_tasks))

    {:noreply, socket}
  end

  def handle_info({:tasks_list_task_moved, _component_id}, socket) do
    sub_tasks =
      Tasks.list_sub_tasks!(socket.assigns.task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:task_state, :assignees, :overdue?]
      )

    send_update(CitadelWeb.Components.TasksListComponent,
      id: "sub-tasks-#{socket.assigns.task.id}",
      tasks: sub_tasks
    )

    socket =
      socket
      |> assign(:sub_tasks, sub_tasks)
      |> assign(:sub_tasks_count, length(sub_tasks))

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{topic: "tasks:task:" <> task_id, payload: _payload},
        socket
      ) do
    if task_id == socket.assigns.task.id do
      task =
        Tasks.get_task!(task_id,
          actor: socket.assigns.current_user,
          tenant: socket.assigns.current_workspace.id,
          load: [:task_state, :user, :parent_task, :ancestors, :assignees, :overdue?]
        )

      {:noreply, assign(socket, :task, task)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{topic: "tasks:task_children:" <> parent_id, payload: payload},
        socket
      ) do
    if parent_id == socket.assigns.task.id do
      {:noreply, handle_sub_task_broadcast(payload, socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{topic: "tasks:task_dependencies:" <> _task_id},
        socket
      ) do
    {task, task_dependencies} = reload_task_with_dependencies(socket)
    {:noreply, socket |> assign(:task, task) |> assign(:task_dependencies, task_dependencies)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{topic: "tasks:task_dependents:" <> _task_id},
        socket
      ) do
    {task, task_dependencies} = reload_task_with_dependencies(socket)
    {:noreply, socket |> assign(:task, task) |> assign(:task_dependencies, task_dependencies)}
  end

  defp handle_sub_task_broadcast(%{action: :destroy} = payload, socket) do
    sub_tasks = Enum.reject(socket.assigns.sub_tasks, &(&1.id == payload.id))
    maybe_notify_sub_task_deleted(sub_tasks, payload, socket)

    socket
    |> assign(:sub_tasks, sub_tasks)
    |> assign(:sub_tasks_count, length(sub_tasks))
  end

  defp handle_sub_task_broadcast(_sub_task, socket) do
    sub_tasks =
      Tasks.list_sub_tasks!(socket.assigns.task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:task_state, :assignees, :overdue?]
      )

    maybe_notify_sub_tasks_updated(sub_tasks, socket)

    socket
    |> assign(:sub_tasks, sub_tasks)
    |> assign(:sub_tasks_count, length(sub_tasks))
  end

  defp maybe_notify_sub_task_deleted(sub_tasks, payload, socket) do
    unless Enum.empty?(sub_tasks) do
      send_update(CitadelWeb.Components.TasksListComponent,
        id: "sub-tasks-#{socket.assigns.task.id}",
        deleted_task: payload
      )
    end
  end

  defp maybe_notify_sub_tasks_updated(sub_tasks, socket) do
    unless Enum.empty?(sub_tasks) do
      send_update(CitadelWeb.Components.TasksListComponent,
        id: "sub-tasks-#{socket.assigns.task.id}",
        tasks: sub_tasks
      )
    end
  end

  defp reload_task_with_dependencies(socket) do
    task =
      Tasks.get_task!(socket.assigns.task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [
          :task_state,
          :user,
          :parent_task,
          :ancestors,
          :assignees,
          :overdue?,
          :blocked?,
          :blocking_count,
          dependencies: [:task_state],
          dependents: [:task_state]
        ]
      )

    task_dependencies =
      Tasks.list_task_dependencies!(task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    {task, task_dependencies}
  end

  defp handle_add_dependency(human_id, socket) do
    case Tasks.add_task_dependency_by_human_id(socket.assigns.task.id, human_id,
           actor: socket.assigns.current_user,
           tenant: socket.assigns.current_workspace.id
         ) do
      {:ok, _dependency} ->
        {task, task_dependencies} = reload_task_with_dependencies(socket)

        {:noreply,
         socket
         |> assign(:task, task)
         |> assign(:task_dependencies, task_dependencies)
         |> put_flash(:info, "Dependency added successfully")}

      {:error, error} ->
        error_message = format_dependency_error(error, human_id)
        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  defp format_dependency_error(error, human_id) do
    cond do
      Exception.message(error) =~ "circular dependency" ->
        "Cannot add dependency: would create a circular dependency"

      Exception.message(error) =~ "task not found" ->
        "Task with ID #{human_id} not found"

      true ->
        "Failed to add dependency"
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_workspace={@current_workspace} workspaces={@workspaces}>
      <div class="relative h-full p-4 bg-base-200 border border-base-300">
        <div class="h-full overflow-auto ">
          <div class="breadcrumbs text-sm mb-4">
            <ul>
              <li><.link navigate={~p"/"}>Tasks</.link></li>
              <li :for={ancestor <- @task.ancestors}>
                <.link navigate={~p"/tasks/#{ancestor.human_id}"}>{ancestor.human_id}</.link>
              </li>
              <li><span>{@task.human_id}</span></li>
            </ul>
          </div>

          <div class="flex items-start justify-between pr-3">
            <div class="flex items-center gap-3 flex-1">
              <%= if @can_edit do %>
                <.live_component
                  module={CitadelWeb.Components.TaskStateDropdown}
                  id={"task-state-#{@task.id}"}
                  task={@task}
                  current_user={@current_user}
                  current_workspace={@current_workspace}
                  size="size-5"
                />
              <% else %>
                <.task_state_icon task_state={@task.task_state} size="size-5" />
              <% end %>
              <%= if @can_edit do %>
                <input
                  type="text"
                  name="title"
                  value={@task.title}
                  phx-blur="save-title"
                  phx-keydown="save-title"
                  phx-key="Enter"
                  class="input input-ghost text-2xl font-bold flex-1 p-0 h-auto min-h-0 focus:outline-none focus:bg-base-300/50 rounded"
                />
              <% else %>
                <h1 class="card-title text-2xl">{@task.title}</h1>
              <% end %>
            </div>
            <div class="flex gap-2">
              <.button
                :if={@can_delete}
                class="btn btn-sm btn-secondary text-error"
                phx-click="confirm_delete"
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </.button>
            </div>
          </div>

          <div class="pt-4"></div>

          <div class="grid grid-cols-[1fr_20rem] gap-4">
            <div class="py-4">
              <h2 class="text-sm font-semibold text-base-content/70 mb-2">Description</h2>
              <div
                id={"description-editor-#{@task.id}"}
                phx-hook="MilkdownEditor"
                phx-update="ignore"
                data-content={@task.description || ""}
                data-readonly={to_string(not @can_edit)}
                class="milkdown-container prose max-w-none"
              />
            </div>

            <div class="border-l border-base-300 p-4">
              <div class="sticky top-0 space-y-5">
                <div class="flex items-center justify-between gap-4">
                  <label class="text-xs font-medium text-base-content/60 uppercase tracking-wide whitespace-nowrap">
                    Priority
                  </label>
                  <%= if @can_edit do %>
                    <.live_component
                      module={CitadelWeb.Components.PriorityDropdown}
                      id={"task-priority-#{@task.id}"}
                      task={@task}
                      current_user={@current_user}
                      current_workspace={@current_workspace}
                      align_right={true}
                    />
                  <% else %>
                    <.priority_badge priority={@task.priority} />
                  <% end %>
                </div>

                <div class="flex items-center justify-between gap-4">
                  <label class="text-xs font-medium text-base-content/60 uppercase tracking-wide whitespace-nowrap">
                    Assignees
                  </label>
                  <%= if @can_edit do %>
                    <.live_component
                      module={CitadelWeb.Components.AssigneeSelect}
                      id={"task-assignees-#{@task.id}"}
                      workspace={@current_workspace}
                      selected_ids={Enum.map(@task.assignees, & &1.id)}
                      field_name="assignees[]"
                      current_user={@current_user}
                      on_change={true}
                      compact={true}
                    />
                  <% else %>
                    <%= if Enum.empty?(@task.assignees) do %>
                      <span class="text-sm text-base-content/40">Unassigned</span>
                    <% else %>
                      <div class="flex flex-wrap gap-1">
                        <.user_avatar
                          :for={assignee <- @task.assignees}
                          user={assignee}
                          size="w-7 h-7"
                        />
                      </div>
                    <% end %>
                  <% end %>
                </div>

                <div class="flex items-center justify-between gap-4">
                  <label class="text-xs font-medium text-base-content/60 uppercase tracking-wide whitespace-nowrap">
                    Due Date
                  </label>
                  <%= if @can_edit do %>
                    <input
                      type="text"
                      name="due_date"
                      value={@task.due_date}
                      phx-blur="save-due-date"
                      placeholder="None"
                      onfocus="this.type='date'"
                      class={[
                        "input input-ghost text-sm text-right p-0 h-auto min-h-0 border-0 placeholder:text-base-content/60",
                        @task.overdue? && "text-error",
                        @task.due_date && !@task.overdue? && "text-base-content/80"
                      ]}
                    />
                  <% else %>
                    <span class={[
                      "text-sm",
                      @task.overdue? && "text-error",
                      !@task.due_date && "text-base-content/40"
                    ]}>
                      {if @task.due_date,
                        do: Calendar.strftime(@task.due_date, "%b %d, %Y"),
                        else: "Not set"}
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <div class="py-4 border-t border-base-300">
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-sm font-semibold text-base-content/70">
                Sub-tasks ({@sub_tasks_count})
              </h2>
              <.button :if={@can_edit} class="btn btn-xs btn-secondary" phx-click="new-sub-task">
                <.icon name="hero-plus" class="size-3" /> Add
              </.button>
            </div>

            <%= if @sub_tasks_count == 0 do %>
              <p class="text-base-content/50 italic text-sm">No sub-tasks</p>
            <% else %>
              <.live_component
                module={CitadelWeb.Components.TasksListComponent}
                id={"sub-tasks-#{@task.id}"}
                tasks={@sub_tasks}
                current_user={@current_user}
                current_workspace={@current_workspace}
              />
            <% end %>
          </div>

          <% # Only show dependencies section if dependencies are loaded
          dependencies_loaded = not match?(%Ash.NotLoaded{}, @task.dependencies)
          dependents_loaded = not match?(%Ash.NotLoaded{}, @task.dependents) %>
          <%= if dependencies_loaded or dependents_loaded do %>
            <div class="py-4 border-t border-base-300">
              <h2 class="text-sm font-semibold text-base-content/70 mb-3">
                Dependencies
                <%= if @task.blocked? do %>
                  <span class="badge badge-warning badge-sm ml-2">Blocked</span>
                <% end %>
              </h2>

              <div class="space-y-4">
                <%= if dependencies_loaded do %>
                  <div>
                    <h3 class="text-xs text-base-content/50 mb-2">Depends on</h3>
                    <%= if @can_edit do %>
                      <form phx-submit="add-dependency" class="flex gap-2 mb-3">
                        <input
                          type="text"
                          name="human_id"
                          placeholder="Task ID (e.g., PER-45)"
                          class="input input-sm input-bordered flex-1"
                        />
                        <button type="submit" class="btn btn-sm btn-secondary">Add</button>
                      </form>
                    <% end %>
                    <%= if Enum.empty?(@task.dependencies) do %>
                      <p class="text-base-content/50 italic text-sm">No dependencies</p>
                    <% else %>
                      <% # Create a map from depends_on_task_id to TaskDependency ID
                      dep_map =
                        Map.new(@task_dependencies, fn td -> {td.depends_on_task_id, td.id} end) %>
                      <div class="space-y-2">
                        <%= for dep <- @task.dependencies do %>
                          <div class="flex items-center justify-between p-2 bg-base-100 rounded-lg border border-base-300">
                            <.link
                              navigate={~p"/tasks/#{dep.human_id}"}
                              class="flex items-center gap-2 flex-1 hover:underline"
                            >
                              <.task_state_icon task_state={dep.task_state} size="size-4" />
                              <span class="text-sm">{dep.human_id}</span>
                              <span class="text-sm text-base-content/70">{dep.title}</span>
                            </.link>
                            <%= if @can_edit do %>
                              <button
                                phx-click="remove-dependency"
                                phx-value-id={Map.get(dep_map, dep.id)}
                                class="btn btn-ghost btn-xs text-error"
                                title="Remove dependency"
                              >
                                <.icon name="hero-x-mark" class="size-4" />
                              </button>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if dependents_loaded and not Enum.empty?(@task.dependents) do %>
                  <div>
                    <h3 class="text-xs text-base-content/50 mb-2">Blocks</h3>
                    <div class="space-y-2">
                      <%= for dependent <- @task.dependents do %>
                        <div class="flex items-center gap-2 p-2 bg-base-100 rounded-lg border border-base-300">
                          <.link
                            navigate={~p"/tasks/#{dependent.human_id}"}
                            class="flex items-center gap-2 flex-1 hover:underline"
                          >
                            <.task_state_icon task_state={dependent.task_state} size="size-4" />
                            <span class="text-sm">{dependent.human_id}</span>
                            <span class="text-sm text-base-content/70">{dependent.title}</span>
                          </.link>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <.live_component
        :if={@show_sub_task_form}
        module={CitadelWeb.Components.NewTaskModal}
        id="new-sub-task-modal"
        current_user={@current_user}
        current_workspace={@current_workspace}
        parent_task_id={@task.id}
        close_event="close-sub-task-form"
      />

      <.live_component
        :if={@confirm_delete}
        module={CitadelWeb.Components.ConfirmationModal}
        id="delete-task-modal"
        title="Delete Task"
        message="Are you sure you want to delete this task? This action cannot be undone."
        confirm_label="Delete"
        cancel_label="Cancel"
        on_confirm="delete"
        on_cancel="cancel_delete"
      />
    </Layouts.app>
    """
  end
end
