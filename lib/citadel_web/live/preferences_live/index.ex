defmodule CitadelWeb.PreferencesLive.Index do
  @moduledoc false

  use CitadelWeb, :live_view

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
  on_mount {CitadelWeb.LiveUserAuth, :load_workspace}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    socket =
      case Map.get(params, "checkout") do
        "success" ->
          put_flash(socket, :info, "Successfully upgraded! Your subscription is now active.")

        "cancelled" ->
          put_flash(socket, :info, "Checkout cancelled.")

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_workspace={@current_workspace} workspaces={@workspaces}>
      <div class="relative h-full overflow-hidden">
        <div class="h-full overflow-auto p-6">
          <h1 class="text-2xl mb-4">Preferences</h1>

          <div class="space-y-6">
            <.live_component
              module={CitadelWeb.Components.OrganizationSection}
              id="organization-section"
              current_user={@current_user}
              current_workspace={@current_workspace}
            />

            <.card class="bg-base-200 border-base-300">
              <:title>
                <div class="flex justify-between items-center w-full">
                  <span>Workspaces</span>
                  <.link navigate={~p"/preferences/workspaces/new"}>
                    <.button variant="primary">New Workspace</.button>
                  </.link>
                </div>
              </:title>
              <.table
                id="workspaces"
                rows={@workspaces}
                row_click={&JS.navigate(~p"/preferences/workspace/#{&1.id}")}
              >
                <:col :let={workspace} label="Name">
                  {workspace.name}
                </:col>
                <:col :let={workspace} label="Role">
                  <%= if workspace.owner_id == @current_user.id do %>
                    Owner
                  <% else %>
                    Member
                  <% end %>
                </:col>
              </.table>
            </.card>

            <.live_component
              module={CitadelWeb.Components.ApiKeysSection}
              id="api-keys-section"
              current_user={@current_user}
            />

            <.live_component
              module={CitadelWeb.Components.PasswordSection}
              id="password-section"
              current_user={@current_user}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
