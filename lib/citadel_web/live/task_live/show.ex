defmodule CitadelWeb.TaskLive.Show do
  @moduledoc false

  use CitadelWeb, :live_view

  alias Citadel.Tasks

  import CitadelWeb.Components.Markdown
  import CitadelWeb.Components.TaskComponents, only: [task_state_icon: 1]

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
  on_mount {CitadelWeb.LiveUserAuth, :load_workspace}

  def mount(%{"id" => id}, _session, socket) do
    task =
      Tasks.get_task_by_human_id!(id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        load: [:task_state, :user, :parent_task, :ancestors, sub_tasks: [:task_state]]
      )

    can_edit = Ash.can?({task, :update}, socket.assigns.current_user)

    socket =
      socket
      |> assign(:task, task)
      |> assign(:can_edit, can_edit)
      |> assign(:editing, false)
      |> assign(:form, nil)
      |> assign(:show_sub_task_form, false)

    {:ok, socket}
  end

  def handle_event("new-sub-task", _params, socket) do
    {:noreply, assign(socket, :show_sub_task_form, true)}
  end

  def handle_event("close-sub-task-form", _params, socket) do
    {:noreply, assign(socket, :show_sub_task_form, false)}
  end

  def handle_event("edit", _params, socket) do
    form =
      socket.assigns.task
      |> AshPhoenix.Form.for_update(:update,
        domain: Tasks,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )
      |> to_form()

    {:noreply, socket |> assign(:editing, true) |> assign(:form, form)}
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
        task = Ash.load!(task, [:task_state, :user], tenant: socket.assigns.current_workspace.id)

        socket =
          socket
          |> assign(:task, task)
          |> assign(:editing, false)
          |> assign(:form, nil)
          |> put_flash(:info, "Task updated successfully")

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_info({:task_created, _sub_task}, socket) do
    task =
      Ash.load!(socket.assigns.task, [sub_tasks: [:task_state]],
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    socket =
      socket
      |> assign(:task, task)
      |> assign(:show_sub_task_form, false)
      |> put_flash(:info, "Sub-task created successfully")

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_workspace={@current_workspace} workspaces={@workspaces}>
      <div class="p-4 bg-base-200 border border-base-300">
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

            <div class="flex gap-2">
              <.button type="submit" class="btn btn-primary">Save</.button>
              <.button type="button" class="btn btn-ghost" phx-click="cancel">Cancel</.button>
            </div>
          </.form>
        <% else %>
          <div class="flex items-start justify-between">
            <div class="flex items-center gap-3 flex-1">
              <.task_state_icon task_state={@task.task_state} size="size-5" />
              <h1 class="card-title text-2xl">
                {@task.title}
              </h1>
            </div>
            <.button :if={@can_edit} class="btn btn-sm btn-secondary" phx-click="edit">
              <.icon name="hero-pencil" class="size-4" /> Edit
            </.button>
          </div>

          <div class="pt-4"></div>

          <div class="py-4">
            <h2 class="text-sm font-semibold text-base-content/70 mb-2">Description</h2>
            <%= if @task.description do %>
              <div class="text-base-content prose max-w-none">{to_markdown(@task.description)}</div>
            <% else %>
              <p class="text-base-content/50 italic">No description provided</p>
            <% end %>
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
              <div class="space-y-2">
                <%= for sub_task <- @task.sub_tasks do %>
                  <.link
                    navigate={~p"/tasks/#{sub_task.human_id}"}
                    class="block p-2 rounded hover:bg-base-200"
                  >
                    <div class="flex items-center gap-2">
                      <.task_state_icon task_state={sub_task.task_state} />
                      <span>{sub_task.title}</span>
                    </div>
                  </.link>
                <% end %>
              </div>
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
    </Layouts.app>
    """
  end
end
