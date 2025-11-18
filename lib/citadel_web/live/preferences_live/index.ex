defmodule CitadelWeb.PreferencesLive.Index do
  @moduledoc false

  use CitadelWeb, :live_view

  alias Citadel.Accounts

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    workspaces =
      Accounts.list_workspaces!(
        actor: socket.assigns.current_user,
        load: [:owner]
      )

    {:ok, assign(socket, :workspaces, workspaces)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl mb-4">Preferences</h1>

      <div>
        <.card class="bg-base-200 border-base-300">
          <:title>Workspaces</:title>
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
      </div>
    </Layouts.app>
    """
  end
end
