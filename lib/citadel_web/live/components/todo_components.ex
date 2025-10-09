defmodule CitadelWeb.Components.TodoComponents do
  @moduledoc false

  use CitadelWeb, :html

  attr :class, :string, default: ""

  def control_bar(assigns) do
    ~H"""
    <div class={["flex p-2 pl-6 border-b border-base-300", @class]}>
      <div>
        <.button class="btn btn-sm btn-neutral" phx-click="new-todo">
          <.icon name="hero-plus" class="size-4" /> New
        </.button>
      </div>
    </div>
    """
  end

  attr :todo_states, :list, required: true
  attr :todos_by_state, :map, required: true

  def todos_list(assigns) do
    ~H"""
    <div class="divide-y divide-base-300" phx-hook="TodoDragDrop" id="todos-container">
      <div :for={state <- @todo_states} class="py-4">
        <div class="px-6 mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">
            {state.name}
          </h2>
          <span class="badge badge-neutral badge-sm">
            {length(Map.get(@todos_by_state, state.id, []))}
          </span>
        </div>

        <div data-dropzone data-state-id={state.id} class="min-h-[50px]">
          <%= if todos = Map.get(@todos_by_state, state.id) do %>
            <.todo :for={todo <- todos} todo={todo} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :todo, :map, required: true

  def todo(assigns) do
    ~H"""
    <div
      class="todo-item flex flex-row justify-between pl-6 py-2 hover:bg-base-100 cursor-move"
      data-todo-id={@todo.id}
    >
      <div class="flex flex-row items-center gap-2">
        <div class="todo-drag-handle flex items-center cursor-grab active:cursor-grabbing">
          <.icon name="hero-bars-3" class="size-4 text-base-content/50" />
        </div>
        <input
          type="checkbox"
          class="checkbox checkbox-xs"
          name="todo_status"
          value="false"
          checked={@todo.todo_state.is_complete}
        />
        <div class="flex flex-col">
          <div class="font-medium text-base-content">{@todo.title}</div>
          <div :if={@todo.description} class="text-sm text-base-content/70">
            {@todo.description}
          </div>
        </div>
      </div>

      <div></div>
    </div>
    """
  end
end
