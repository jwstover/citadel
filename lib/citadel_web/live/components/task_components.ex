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
  attr :current_user, :any, required: true
  attr :current_workspace, :any, required: true

  def tasks_list(assigns) do
    ~H"""
    <table class="w-full" phx-hook="TaskDragDrop" id="tasks-container">
      <tbody
        :for={state <- @task_states}
        data-dropzone
        data-state-id={state.id}
        class="[&:not(:first-child)]:border-t [&:not(:first-child)]:border-border"
      >
        <tr class="sticky top-0 bg-base-200 z-100">
          <td colspan="7" class="px-6 py-4">
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
        <tr class="sticky top-[60px] bg-base-200 z-100">
          <th></th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 px-2"></th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left px-2">ID</th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left ">Name</th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left px-2">
            Priority
          </th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left px-2">
            Due Date
          </th>
          <th class="text-xs uppercase text-base-content/50 font-semibold pb-2 text-left px-2">
            Assignee
          </th>
        </tr>
        <%= if tasks = Map.get(@tasks_by_state, state.id) do %>
          <.task_row
            :for={task <- tasks}
            task={task}
            current_user={@current_user}
            current_workspace={@current_workspace}
          />
        <% end %>
      </tbody>
    </table>
    """
  end

  attr :task, :map, required: true
  attr :current_user, :any, required: true
  attr :current_workspace, :any, required: true

  def task_row(assigns) do
    ~H"""
    <tr class="task-item hover:bg-base-100" data-task-id={@task.id}>
      <td class="pl-6 p-2 w-8 align-middle">
        <div class="task-drag-handle flex items-center cursor-grab active:cursor-grabbing">
          <.icon name="hero-bars-3" class="size-4 text-base-content/50" />
        </div>
      </td>
      <td class="p-2 w-6">
        <div class="flex items-center justify-center">
          <.live_component
            module={CitadelWeb.Components.TaskStateDropdown}
            id={"task-state-#{@task.id}"}
            task={@task}
            current_user={@current_user}
            current_workspace={@current_workspace}
            size="size-4"
          />
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
      <td class="p-2 w-24 align-middle">
        <.live_component
          module={CitadelWeb.Components.PriorityDropdown}
          id={"task-priority-#{@task.id}"}
          task={@task}
          current_user={@current_user}
          current_workspace={@current_workspace}
        />
      </td>
      <td class="p-2 w-28 align-middle whitespace-nowrap">
        <.due_date_display due_date={@task.due_date} overdue={@task.overdue?} />
      </td>
      <td class="p-2 w-24 align-middle">
        <.assignee_avatars assignees={@task.assignees} />
      </td>
    </tr>
    """
  end

  attr :task_state, TaskState, required: true
  attr :size, :string, default: "size-4"

  def task_state_icon(assigns) do
    ~H"""
    <.icon name={@task_state.icon} class={@size} style={"color: #{@task_state.background_color}"} />
    """
  end

  attr :priority, :atom, required: true

  def priority_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      priority_badge_class(@priority)
    ]}>
      {@priority}
    </span>
    """
  end

  defp priority_badge_class(:low), do: "badge-ghost"
  defp priority_badge_class(:medium), do: "badge-info"
  defp priority_badge_class(:high), do: "badge-warning"
  defp priority_badge_class(:urgent), do: "badge-error"
  defp priority_badge_class(_), do: "badge-ghost"

  attr :due_date, :any, required: true
  attr :overdue, :boolean, default: false

  def due_date_display(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@due_date) -> %>
        <span class="text-base-content/30">—</span>
      <% @due_date == Date.utc_today() -> %>
        <span class="text-warning font-medium">Today</span>
      <% @overdue -> %>
        <span class="text-error font-medium">{format_date(@due_date)}</span>
      <% true -> %>
        <span class="text-base-content/70">{format_date(@due_date)}</span>
    <% end %>
    """
  end

  defp format_date(date) do
    Calendar.strftime(date, "%b %d")
  end

  attr :assignees, :list, required: true
  attr :max_display, :integer, default: 3

  def assignee_avatars(assigns) do
    assigns =
      assigns
      |> assign(:visible_assignees, Enum.take(assigns.assignees, assigns.max_display))
      |> assign(:overflow_count, max(0, length(assigns.assignees) - assigns.max_display))

    ~H"""
    <div class="flex -space-x-2">
      <%= if @assignees == [] do %>
        <span class="text-base-content/30">—</span>
      <% else %>
        <.user_avatar :for={assignee <- @visible_assignees} user={assignee} />
        <div
          :if={@overflow_count > 0}
          class="avatar avatar-placeholder"
          title={"#{@overflow_count} more"}
        >
          <div class="w-6 h-6 rounded-full bg-base-300 text-xs flex items-center justify-center">
            +{@overflow_count}
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :user, :any, required: true
  attr :size, :string, default: "w-6 h-6"
  attr :text_size, :string, default: "text-xs"

  def user_avatar(assigns) do
    ~H"""
    <div class="avatar avatar-placeholder" title={to_string(@user.email)}>
      <div class={["rounded-full bg-base-300 flex items-center justify-center", @size, @text_size]}>
        {get_initial(@user.email)}
      </div>
    </div>
    """
  end

  defp get_initial(%Ash.CiString{string: string}), do: get_initial(string)

  defp get_initial(email) when is_binary(email) do
    email
    |> String.first()
    |> String.upcase()
  end

  defp get_initial(_), do: "?"
end
