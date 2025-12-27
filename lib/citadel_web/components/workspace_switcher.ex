defmodule CitadelWeb.Components.WorkspaceSwitcher do
  @moduledoc """
  Workspace switcher dropdown component for the navbar.
  Groups workspaces by their organization.
  """

  use Phoenix.Component
  use CitadelWeb, :verified_routes
  import CitadelWeb.CoreComponents

  attr :current_workspace, :any, required: true
  attr :workspaces, :list, required: true

  def workspace_switcher(assigns) do
    grouped_workspaces =
      assigns.workspaces
      |> Enum.group_by(& &1.organization)
      |> Enum.sort_by(fn {org, _workspaces} -> org.name end)

    assigns = assign(assigns, :grouped_workspaces, grouped_workspaces)

    ~H"""
    <div class="dropdown">
      <div tabindex="0" role="button" class="btn btn-secondary btn-sm gap-2">
        <.icon name="hero-building-office" class="h-5 w-5" />
        <span class="hidden sm:inline">{@current_workspace.name}</span>
        <.icon name="hero-chevron-down" class="h-4 w-4" />
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-200 rounded-box z-[1] w-64 p-2 shadow-lg mt-3"
      >
        <li class="menu-title px-4 py-2">
          <span class="text-xs font-semibold">Switch Workspace</span>
        </li>
        <%= for {org, org_workspaces} <- @grouped_workspaces do %>
          <li class="menu-title px-4 pt-3 pb-1">
            <span class="text-xs text-base-content/50">{org.name}</span>
          </li>
          <%= for workspace <- org_workspaces do %>
            <li>
              <button
                phx-click="switch-workspace"
                phx-value-workspace-id={workspace.id}
                class={[
                  "flex items-center justify-between",
                  workspace.id == @current_workspace.id && "active"
                ]}
              >
                <span class="flex-1 truncate">{workspace.name}</span>
                <%= if workspace.id == @current_workspace.id do %>
                  <.icon name="hero-check" class="h-4 w-4" />
                <% end %>
              </button>
            </li>
          <% end %>
        <% end %>
        <li class="border-t border-base-300 mt-2">
          <.link navigate={~p"/preferences"} class="text-sm">
            <.icon name="hero-cog-6-tooth" class="h-4 w-4" /> Manage Workspaces
          </.link>
        </li>
      </ul>
    </div>
    """
  end
end
