defmodule CitadelWeb.Components.TaskDependencies do
  @moduledoc false

  use CitadelWeb, :live_component

  import CitadelWeb.Components.TaskComponents, only: [task_state_icon: 1]

  def update(assigns, socket) do
    dependencies_loaded = not match?(%Ash.NotLoaded{}, assigns.task.dependencies)
    dependents_loaded = not match?(%Ash.NotLoaded{}, assigns.task.dependents)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:task_dependencies, fn -> [] end)
     |> assign(:dependencies_loaded, dependencies_loaded)
     |> assign(:dependents_loaded, dependents_loaded)}
  end

  def render(assigns) do
    ~H"""
    <div class="py-4 border-t border-base-300">
      <%= if @dependencies_loaded or @dependents_loaded do %>
        <h2 class="text-sm font-semibold text-base-content/70 mb-3">
          Blocked by
          <%= if @task.blocked? do %>
            <span class="badge badge-warning badge-sm ml-2">Blocked</span>
          <% end %>
        </h2>

        <div class="space-y-4">
          <%= if @dependencies_loaded do %>
            <div class="max-w-lg">
              <%= if @can_edit do %>
                <form phx-submit="add-dependency" class="flex gap-2 mb-3">
                  <input
                    type="text"
                    name="human_id"
                    placeholder="Add dependency (e.g., PER-45)"
                    class="input input-sm input-bordered flex-1"
                  />
                  <button type="submit" class="btn btn-sm btn-secondary">Add</button>
                </form>
              <% end %>
              <%= if Enum.empty?(@task.dependencies) do %>
                <p class="text-base-content/50 italic text-sm">None</p>
              <% else %>
                <% # Create a map from depends_on_task_id to TaskDependency ID
                dep_map =
                  Map.new(@task_dependencies, fn td -> {td.depends_on_task_id, td.id} end) %>
                <div class="space-y-2">
                  <%= for dep <- @task.dependencies do %>
                    <div class="flex items-center justify-between p-2 bg-base-100 rounded-lg border border-base-300">
                      <.link
                        navigate={~p"/tasks/#{dep.human_id}"}
                        class="flex items-center gap-2 flex-1 hover:underline"
                      >
                        <.task_state_icon task_state={dep.task_state} size="size-4" />
                        <span class="text-sm">{dep.human_id}</span>
                        <span class="text-sm text-base-content/70">{dep.title}</span>
                      </.link>
                      <%= if @can_edit do %>
                        <button
                          phx-click="remove-dependency"
                          phx-value-id={Map.get(dep_map, dep.id)}
                          class="btn btn-ghost btn-xs text-error"
                          title="Remove dependency"
                        >
                          <.icon name="hero-x-mark" class="size-4" />
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>

          <%= if @dependents_loaded and not Enum.empty?(@task.dependents) do %>
            <div>
              <h2 class="text-sm font-semibold text-base-content/70 mb-3">Blocks</h2>
              <div class="space-y-2">
                <%= for dependent <- @task.dependents do %>
                  <div class="flex items-center gap-2 p-2 bg-base-100 rounded-lg border border-base-300">
                    <.link
                      navigate={~p"/tasks/#{dependent.human_id}"}
                      class="flex items-center gap-2 flex-1 hover:underline"
                    >
                      <.task_state_icon task_state={dependent.task_state} size="size-4" />
                      <span class="text-sm">{dependent.human_id}</span>
                      <span class="text-sm text-base-content/70">{dependent.title}</span>
                    </.link>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
