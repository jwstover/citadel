defmodule CitadelWeb.Components.TaskComponents do
  @moduledoc false

  use CitadelWeb, :html

  alias Citadel.Tasks.TaskState

  attr :class, :string, default: ""

  def control_bar(assigns) do
    ~H"""
    <div class={["flex p-2 pl-6 border-b border-base-300", @class]}>
      <div>
        <.button class="btn btn-sm btn-neutral" phx-click="new-task">
          <.icon name="hero-plus" class="size-4" /> New
        </.button>
      </div>
    </div>
    """
  end

  attr :task_states, :list, required: true
  attr :tasks_by_state, :map, required: true

  def tasks_list(assigns) do
    ~H"""
    <div class="divide-y divide-base-300" phx-hook="TaskDragDrop" id="tasks-container">
      <div :for={state <- @task_states} class="py-4">
        <div class="px-6 mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">
            {state.name}
          </h2>
          <span class="badge badge-neutral badge-sm">
            {length(Map.get(@tasks_by_state, state.id, []))}
          </span>
        </div>

        <div data-dropzone data-state-id={state.id} class="min-h-[50px]">
          <%= if tasks = Map.get(@tasks_by_state, state.id) do %>
            <.task :for={task <- tasks} task={task} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :task, :map, required: true

  def task(assigns) do
    ~H"""
    <div
      class="task-item flex flex-row justify-between pl-6 py-2 hover:bg-base-100"
      data-task-id={@task.id}
    >
      <div class="flex flex-row items-center gap-2 flex-1">
        <div class="task-drag-handle flex items-center cursor-grab active:cursor-grabbing">
          <.icon name="hero-bars-3" class="size-4 text-base-content/50" />
        </div>
        <.task_state_icon task_state={@task.task_state} />
        <.link
          navigate={~p"/tasks/#{@task.id}"}
          class="flex flex-col flex-1 cursor-pointer hover:underline"
        >
          <div class="font-medium text-base-content">{@task.title}</div>
          <div :if={@task.description} class="text-sm text-base-content/70">
            {@task.description}
          </div>
        </.link>
      </div>

      <div></div>
    </div>
    """
  end

  attr :task_state, TaskState, required: true

  def task_state_icon(assigns) do
    ~H"""
    <%= case @task_state.name do %>
      <% "Todo" -> %>
        <.icon name="fa-circle-regular" class="text-sky-600 size-4" />
      <% "In Progress" -> %>
        <.icon name="fa-circle-half-stroke-solid" class="text-yellow-500 size-4" />
      <% "Complete" -> %>
        <.icon name="fa-circle-solid" class="size-4" />
    <% end %>
    """
  end
end
