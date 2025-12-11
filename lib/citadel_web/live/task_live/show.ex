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
          sub_tasks: [:task_state, :assignees, :overdue?]
        ]
      )

    can_edit = Ash.can?({task, :update}, socket.assigns.current_user)
    can_delete = Ash.can?({task, :destroy}, socket.assigns.current_user)

    socket =
      socket
      |> assign(:task, task)
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
              :overdue?,
              sub_tasks: [:task_state, :assignees, :overdue?]
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
                :overdue?,
                sub_tasks: [:task_state, :assignees, :overdue?]
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
                :overdue?,
                sub_tasks: [:task_state, :assignees, :overdue?]
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
    task =
      Ash.load!(socket.assigns.task, [sub_tasks: [:task_state, :assignees, :overdue?]],
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    send_update(CitadelWeb.Components.TasksListComponent,
      id: "sub-tasks-#{task.id}",
      tasks: task.sub_tasks
    )

    socket =
      socket
      |> assign(:task, task)
      |> assign(:show_sub_task_form, false)
      |> put_flash(:info, "Sub-task created successfully")

    {:noreply, socket}
  end

  def handle_info({:task_priority_changed, task}, socket) do
    {:noreply, assign(socket, :task, %{socket.assigns.task | priority: task.priority})}
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
              :overdue?,
              sub_tasks: [:task_state, :assignees, :overdue?]
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
          sub_tasks: [:task_state, :assignees, :overdue?]
        ],
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    send_update(CitadelWeb.Components.TasksListComponent,
      id: "sub-tasks-#{task.id}",
      tasks: task.sub_tasks
    )

    {:noreply, assign(socket, :task, task)}
  end

  def handle_info({:tasks_list_task_moved, _component_id}, socket) do
    task =
      Ash.load!(socket.assigns.task, [sub_tasks: [:task_state, :assignees, :overdue?]],
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    send_update(CitadelWeb.Components.TasksListComponent,
      id: "sub-tasks-#{task.id}",
      tasks: task.sub_tasks
    )

    {:noreply, assign(socket, :task, task)}
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
                Sub-tasks ({length(@task.sub_tasks)})
              </h2>
              <.button :if={@can_edit} class="btn btn-xs btn-secondary" phx-click="new-sub-task">
                <.icon name="hero-plus" class="size-3" /> Add
              </.button>
            </div>

            <%= if Enum.empty?(@task.sub_tasks) do %>
              <p class="text-base-content/50 italic text-sm">No sub-tasks</p>
            <% else %>
              <.live_component
                module={CitadelWeb.Components.TasksListComponent}
                id={"sub-tasks-#{@task.id}"}
                tasks={@task.sub_tasks}
                current_user={@current_user}
                current_workspace={@current_workspace}
              />
            <% end %>
          </div>
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
