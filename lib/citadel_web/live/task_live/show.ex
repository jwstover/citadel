defmodule CitadelWeb.TaskLive.Show do
  @moduledoc false

  use CitadelWeb, :live_view

  alias Citadel.Tasks

  import CitadelWeb.Components.Markdown

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    task = Tasks.get_task!(id, actor: socket.assigns.current_user, load: [:task_state, :user])

    can_edit = Tasks.can_update_task?(socket.assigns.current_user, task)

    socket =
      socket
      |> assign(:task, task)
      |> assign(:can_edit, can_edit)
      |> assign(:editing, false)
      |> assign(:form, nil)

    {:ok, socket}
  end

  def handle_event("edit", _params, socket) do
    form =
      socket.assigns.task
      |> AshPhoenix.Form.for_update(:update, domain: Tasks)
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
        task = Ash.load!(task, [:task_state, :user])

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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="p-4">
        <div class="mb-4">
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="size-4" /> Back to Tasks
          </.link>
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
              <.task_state_icon task_state={@task.task_state} />
              <h1 class="card-title text-2xl">{@task.title}</h1>
            </div>
            <.button :if={@can_edit} class="btn btn-sm btn-outline" phx-click="edit">
              <.icon name="hero-pencil" class="size-4" /> Edit
            </.button>
          </div>

          <div class="py-4">
            <h2 class="text-sm font-semibold text-base-content/70 mb-2">Description</h2>
            <%= if @task.description do %>
              <div class="text-base-content prose max-w-none">{to_markdown(@task.description)}</div>
            <% else %>
              <p class="text-base-content/50 italic">No description provided</p>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp task_state_icon(assigns) do
    ~H"""
    <%= case @task_state.name do %>
      <% "Todo" -> %>
        <.icon name="fa-circle-regular" class="text-sky-600 size-6" />
      <% "In Progress" -> %>
        <.icon name="fa-circle-half-stroke-solid" class="text-yellow-500 size-6" />
      <% "Complete" -> %>
        <.icon name="fa-circle-solid" class="size-6" />
    <% end %>
    """
  end
end
