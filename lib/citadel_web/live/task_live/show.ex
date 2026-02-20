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

    activities =
      Tasks.list_task_activities!(task.id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:user]
      )

    can_edit = Ash.can?({task, :update}, socket.assigns.current_user)
    can_delete = Ash.can?({task, :destroy}, socket.assigns.current_user)

    if connected?(socket) do
      CitadelWeb.Endpoint.subscribe("tasks:task:#{task.id}")
      CitadelWeb.Endpoint.subscribe("tasks:task_children:#{task.id}")
      CitadelWeb.Endpoint.subscribe("tasks:task_dependencies:#{task.id}")
      CitadelWeb.Endpoint.subscribe("tasks:task_dependents:#{task.id}")
      CitadelWeb.Endpoint.subscribe("tasks:task_activities:#{task.id}")
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
      |> stream(:activities, activities)

    {:ok, socket}
  end

  def handle_event("submit-comment", %{"body" => body}, socket) do
    body = String.trim(body)

    if body == "" do
      {:noreply, socket}
    else
      activity =
        Tasks.create_comment!(
          %{body: body, task_id: socket.assigns.task.id},
          actor: socket.assigns.current_user,
          tenant: socket.assigns.current_workspace.id
        )

      activity = Ash.load!(activity, [:user], tenant: socket.assigns.current_workspace.id)

      {:noreply, stream_insert(socket, :activities, activity)}
    end
  end

  def handle_event("delete-comment", %{"id" => activity_id}, socket) do
    activity =
      Ash.get!(Citadel.Tasks.TaskActivity, activity_id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    Tasks.destroy_comment!(activity,
      actor: socket.assigns.current_user,
      tenant: socket.assigns.current_workspace.id
    )

    {:noreply, stream_delete(socket, :activities, activity)}
  end

  def handle_event("new-sub-task", _params, socket) do
    {:noreply, assign(socket, :show_sub_task_form, true)}
  end

  def handle_event("close-sub-task-form", _params, socket) do
    {:noreply, assign(socket, :show_sub_task_form, false)}
  end

  def handle_event("add-dependency", %{"human_id" => human_id}, socket) do
    human_id = String.trim(human_id)

    if human_id == "" do
      {:noreply, socket}
    else
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
        redirect_path =
          if parent_task, do: ~p"/tasks/#{parent_task.human_id}", else: ~p"/dashboard"

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
        %Phoenix.Socket.Broadcast{
          topic: "tasks:task_activities:" <> _task_id,
          event: "create_comment",
          payload: %{data: activity}
        },
        socket
      ) do
    activity = Ash.load!(activity, [:user], tenant: socket.assigns.current_workspace.id)
    {:noreply, stream_insert(socket, :activities, activity)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "tasks:task_activities:" <> _task_id,
          event: "destroy_comment",
          payload: %{data: activity}
        },
        socket
      ) do
    {:noreply, stream_delete(socket, :activities, activity)}
  end

  attr :activity, :map, required: true

  defp activity_actor_avatar(%{activity: %{actor_type: :user, user: user}} = assigns)
       when not is_nil(user) do
    assigns = assign(assigns, :user, user)

    ~H"""
    <.user_avatar user={@user} />
    """
  end

  defp activity_actor_avatar(%{activity: %{actor_type: :system}} = assigns) do
    ~H"""
    <div class="avatar avatar-placeholder">
      <div class="w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs">
        <.icon name="hero-cog-6-tooth" class="size-3.5 text-base-content/60" />
      </div>
    </div>
    """
  end

  defp activity_actor_avatar(%{activity: %{actor_type: :ai}} = assigns) do
    ~H"""
    <div class="avatar avatar-placeholder">
      <div class="w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs">
        <.icon name="hero-cpu-chip" class="size-3.5 text-base-content/60" />
      </div>
    </div>
    """
  end

  defp activity_actor_avatar(assigns) do
    ~H"""
    <div class="avatar avatar-placeholder">
      <div class="w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs">
        ?
      </div>
    </div>
    """
  end

  attr :activity, :map, required: true

  defp activity_actor_name(%{activity: %{actor_type: :user, user: user}} = assigns)
       when not is_nil(user) do
    assigns = assign(assigns, :user, user)

    ~H"""
    {to_string(@user.email)}
    """
  end

  defp activity_actor_name(%{activity: %{actor_display_name: name}} = assigns)
       when not is_nil(name) do
    assigns = assign(assigns, :name, name)

    ~H"""
    {@name}
    """
  end

  defp activity_actor_name(assigns) do
    ~H"""
    Unknown
    """
  end

  defp relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86_400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86_400)} days ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_workspace={@current_workspace} workspaces={@workspaces}>
      <div class="relative h-full p-4 bg-base-200 border border-base-300">
        <div class="h-full overflow-auto ">
          <div class="breadcrumbs text-sm mb-4">
            <ul>
              <li><.link navigate={~p"/dashboard"}>Tasks</.link></li>
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

          <.live_component
            module={CitadelWeb.Components.TaskDependencies}
            id={"task-dependencies-#{@task.id}"}
            task={@task}
            task_dependencies={@task_dependencies}
            can_edit={@can_edit}
            current_user={@current_user}
            current_workspace={@current_workspace}
          />

          <div class="py-4 border-t border-base-300">
            <div class="flex items-center justify-between mb-3 mr-6">
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

          <div class="py-4 border-t border-base-300">
            <h2 class="text-sm font-semibold text-base-content/70 mb-4">Activity</h2>

            <div id="activities" phx-update="stream" class="space-y-4 mb-6">
              <div id="activities-empty" class="hidden only:block text-base-content/50 italic text-sm">
                No activity yet
              </div>
              <div
                :for={{dom_id, activity} <- @streams.activities}
                id={dom_id}
                class="flex gap-3 group"
              >
                <div class="flex-shrink-0 pt-0.5">
                  <.activity_actor_avatar activity={activity} />
                </div>
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium text-base-content">
                      <.activity_actor_name activity={activity} />
                    </span>
                    <span class="text-xs text-base-content/40">
                      {relative_time(activity.inserted_at)}
                    </span>
                    <button
                      :if={activity.user_id == @current_user.id}
                      phx-click="delete-comment"
                      phx-value-id={activity.id}
                      class="text-xs text-base-content/30 hover:text-error opacity-0 group-hover:opacity-100 transition-opacity"
                      data-confirm="Delete this comment?"
                    >
                      <.icon name="hero-trash" class="size-3" />
                    </button>
                  </div>
                  <p class="text-sm text-base-content/80 mt-0.5 whitespace-pre-wrap">
                    {activity.body}
                  </p>
                </div>
              </div>
            </div>

            <form id="comment-form" phx-submit="submit-comment" class="flex gap-3">
              <div class="flex-shrink-0 pt-0.5">
                <.user_avatar user={@current_user} />
              </div>
              <div class="flex-1">
                <textarea
                  name="body"
                  rows="2"
                  placeholder="Add a comment..."
                  class="textarea textarea-bordered w-full text-sm resize-none"
                  phx-hook="ClearOnSubmit"
                  id="comment-body"
                />
                <div class="flex justify-end mt-2">
                  <button type="submit" class="btn btn-sm btn-primary">
                    Comment
                  </button>
                </div>
              </div>
            </form>
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
