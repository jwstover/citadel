defmodule CitadelWeb.Components.TaskComponents do
  @moduledoc false

  use CitadelWeb, :html

  alias Citadel.Tasks.TaskState

  attr :class, :string, default: ""

  def control_bar(assigns) do
    ~H"""
    <div class={["flex p-2 pl-6 border-b border-border", @class]}>
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
    <table class="w-full" phx-hook="TaskDragDrop" id="tasks-container">
      <tbody
        :for={state <- @task_states}
        data-dropzone
        data-state-id={state.id}
        class="[&:not(:first-child)]:border-t [&:not(:first-child)]:border-border"
      >
        <tr>
          <td colspan="4" class="px-6 py-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-base-content">
                {state.name}
              </h2>
              <span class="badge badge-neutral badge-sm">
                {length(Map.get(@tasks_by_state, state.id, []))}
              </span>
            </div>
          </td>
        </tr>
        <%= if tasks = Map.get(@tasks_by_state, state.id) do %>
          <.task_row :for={task <- tasks} task={task} />
        <% end %>
      </tbody>
    </table>
    """
  end

  attr :task, :map, required: true

  def task_row(assigns) do
    ~H"""
    <tr class="task-item hover:bg-base-100" data-task-id={@task.id}>
      <td class="pl-6 p-2 w-8 align-middle">
        <div class="task-drag-handle flex items-center cursor-grab active:cursor-grabbing">
          <.icon name="hero-bars-3" class="size-4 text-base-content/50" />
        </div>
      </td>
      <td class="p-2 w-6">
        <div class="flex items-center">
          <.task_state_icon task_state={@task.task_state} />
        </div>
      </td>
      <td class="p-2 w-px text-base-content/50 whitespace-nowrap align-middle">
        <.link navigate={~p"/tasks/#{@task.human_id}"} class="hover:underline">
          {@task.human_id}
        </.link>
      </td>
      <td class="py-2 font-medium text-base-content align-middle">
        <.link navigate={~p"/tasks/#{@task.human_id}"} class="hover:underline">
          {@task.title}
        </.link>
      </td>
    </tr>
    """
  end

  attr :task_state, TaskState, required: true
  attr :size, :string, default: "size-4"

  def task_state_icon(assigns) do
    ~H"""
    <%= case @task_state.name do %>
      <% "Todo" -> %>
        <.icon name="fa-circle-regular" class={"text-sky-600 #{@size}"} />
      <% "In Progress" -> %>
        <.icon name="fa-circle-half-stroke-solid" class={"text-yellow-500 #{@size}"} />
      <% "Complete" -> %>
        <.icon name="fa-circle-solid" class={"text-green-600 #{@size}"} />
    <% end %>
    """
  end
end
