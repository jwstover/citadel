defmodule CitadelWeb.Components.NewTaskModal do
  @moduledoc false

  use CitadelWeb, :live_component

  require Logger

  alias Citadel.Tasks.Task

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:parent_task_id, fn -> nil end)
      |> assign_new(:close_event, fn -> "close-new-task-form" end)
      |> assign_form()

    {:ok, socket}
  end

  def handle_event("create", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form,
           params: params,
           action_opts: [
             actor: socket.assigns.current_user,
             tenant: socket.assigns.current_workspace.id
           ]
         ) do
      {:ok, task} ->
        send(self(), {:task_created, task})
        {:noreply, socket}

      {:error, form} ->
        Logger.error("Error creating task: #{inspect(form)}")
        {:noreply, socket |> assign(:form, form)}
    end
  end

  defp assign_form(socket) do
    form =
      AshPhoenix.Form.for_create(Task, :create,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        prepare_params: fn params, _context ->
          params
          |> Map.put("workspace_id", socket.assigns.current_workspace.id)
          |> Map.put("parent_task_id", socket.assigns.parent_task_id)
        end
      )
      |> to_form()

    assign(socket, :form, form)
  end

  def render(assigns) do
    ~H"""
    <dialog id={@id} class="modal modal-open">
      <div class="modal-box" phx-click-away={@close_event}>
        <form method="dialog">
          <button
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
            phx-click={@close_event}
          >
            ✕
          </button>
        </form>
        <h3 class="text-lg font-bold mb-2">
          {if @parent_task_id, do: "New Sub-task", else: "New Task"}
        </h3>

        <.form for={@form} phx-submit="create" phx-target={@myself}>
          <.input field={@form[:title]} placeholder="Title" />
          <.input type="textarea" field={@form[:description]} placeholder="Description" />
          <.button variant="primary" type="submit">Save</.button>
        </.form>
      </div>
    </dialog>
    """
  end
end
