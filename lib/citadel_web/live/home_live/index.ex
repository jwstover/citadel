defmodule CitadelWeb.HomeLive.Index do
  @moduledoc false

  use CitadelWeb, :live_view

  import CitadelWeb.Components.TodoComponents

  alias Citadel.Todos

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Load todo states ordered by their order field
      todo_states = Todos.list_todo_states!(query: [sort: [order: :asc]])

      socket =
        socket
        |> assign(:todo_states, todo_states)
        |> assign_todos()
        |> assign(:show_todo_form, false)

      {:ok, socket}
    else
      {:ok, assign(socket, todo_states: [], todos_by_state: %{}, show_todo_form: false)}
    end
  end

  def handle_event("new-todo", _params, socket) do
    {:noreply, socket |> assign(:show_todo_form, true)}
  end

  def handle_event("close-new-todo-form", _params, socket) do
    {:noreply, socket |> assign(:show_todo_form, false)}
  end

  def handle_event("todo-moved", %{"todo_id" => todo_id, "new_state_id" => new_state_id}, socket) do
    Todos.update_todo!(todo_id, %{todo_state_id: new_state_id},
      actor: socket.assigns.current_user
    )

    {:noreply, assign_todos(socket)}
  end

  def handle_info({:todo_created, _todo}, socket) do
    {:noreply, assign_todos(socket) |> assign(:show_todo_form, false)}
  end

  defp assign_todos(socket) do
    todos =
      Todos.list_todos!(
        actor: socket.assigns.current_user,
        load: [:todo_state]
      )

    todos_by_state = Enum.group_by(todos, & &1.todo_state_id)

    assign(socket, :todos_by_state, todos_by_state)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.control_bar />

      <.todos_list todo_states={@todo_states} todos_by_state={@todos_by_state} />

      <.live_component
        :if={@show_todo_form}
        module={CitadelWeb.Components.NewTodoModal}
        id="new-todo-modal"
        current_user={@current_user}
      />
    </Layouts.app>
    """
  end
end
