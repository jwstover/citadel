defmodule CitadelWeb.TaskLive.Show do
  @moduledoc false

  use CitadelWeb, :live_view

  alias Citadel.Tasks

  import CitadelWeb.Components.TaskComponents, only: [task_state_icon: 1]

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
      |> assign(:editing, false)
      |> assign(:form, nil)
      |> assign(:assignee_ids, Enum.map(task.assignees, & &1.id))
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

  def handle_event("edit", _params, socket) do
    task = socket.assigns.task
    assignee_ids = Enum.map(task.assignees, & &1.id)

    form =
      task
      |> AshPhoenix.Form.for_update(:update,
        domain: Tasks,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )
      |> to_form()

    socket =
      socket
      |> assign(:editing, true)
      |> assign(:form, form)
      |> assign(:assignee_ids, assignee_ids)

    {:noreply, socket}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, socket |> assign(:editing, false) |> assign(:form, nil)}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, task} ->
        task =
          Ash.load!(task, [:task_state, :user, :parent_task, :ancestors, :assignees, sub_tasks: [:task_state]],
            tenant: socket.assigns.current_workspace.id
          )

        socket =
          socket
          |> assign(:task, task)
          |> assign(:editing, false)
          |> assign(:form, nil)
          |> assign(:assignee_ids, Enum.map(task.assignees, & &1.id))
          |> put_flash(:info, "Task updated successfully")

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
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
          Ash.load!(task, [:task_state, :user, :parent_task, :ancestors, :assignees, sub_tasks: [:task_state]],
            tenant: socket.assigns.current_workspace.id
          )

        {:noreply, assign(socket, :task, task)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save description")}
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
      <div class="h-full overflow-auto p-4 bg-base-200 border border-base-300">
        <div class="breadcrumbs text-sm mb-4">
          <ul>
            <li><.link navigate={~p"/"}>Tasks</.link></li>
            <li :for={ancestor <- @task.ancestors}>
              <.link navigate={~p"/tasks/#{ancestor.human_id}"}>{ancestor.human_id}</.link>
            </li>
            <li><span>{@task.human_id}</span></li>
          </ul>
        </div>

        <%= if @editing do %>
          <.form for={@form} id="task-form" phx-change="validate" phx-submit="save">
            <.input field={@form[:title]} type="text" label="Title" />
            <.input field={@form[:description]} type="textarea" label="Description" />

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:priority]}
                type="select"
                label="Priority"
                options={[Low: :low, Medium: :medium, High: :high, Urgent: :urgent]}
              />
              <.input field={@form[:due_date]} type="date" label="Due Date" />
            </div>

            <div class="fieldset mb-2">
              <label>
                <span class="label mb-1">Assignees</span>
                <.live_component
                  module={CitadelWeb.Components.AssigneeSelect}
                  id="task-assignees"
                  workspace={@current_workspace}
                  selected_ids={@assignee_ids}
                  field_name="form[assignees][]"
                  current_user={@current_user}
                />
              </label>
            </div>

            <div class="flex gap-2">
              <.button type="submit" class="btn btn-primary">Save</.button>
              <.button type="button" class="btn btn-ghost" phx-click="cancel">Cancel</.button>
            </div>
          </.form>
        <% else %>
          <div class="flex items-start justify-between">
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
              <h1 class="card-title text-2xl">
                {@task.title}
              </h1>
            </div>
            <div class="flex gap-2">
              <.button :if={@can_edit} class="btn btn-sm btn-secondary" phx-click="edit">
                <.icon name="hero-pencil" class="size-4" /> Edit
              </.button>
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
        <% end %>
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
