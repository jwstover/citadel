defmodule CitadelWeb.PreferencesLive.Workspace do
  @moduledoc false

  use CitadelWeb, :live_view

  alias Citadel.Accounts
  alias Citadel.Integrations

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
  on_mount {CitadelWeb.LiveUserAuth, :load_workspace}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:show_invite_modal, false)
     |> assign(:show_leave_confirmation, false)
     |> assign(:show_github_modal, false)
     |> assign(:show_disconnect_confirmation, false)}
  end

  def handle_params(%{"id" => workspace_id}, _uri, socket) do
    current_user = socket.assigns.current_user

    # Try to load workspace - will fail if user doesn't have access
    case load_workspace_data(workspace_id, current_user) do
      {:ok, workspace, memberships, invitations} ->
        is_owner = workspace.owner_id == current_user.id
        github_connection = load_github_connection(workspace_id, current_user)

        {:noreply,
         socket
         |> assign(:workspace, workspace)
         |> assign(:memberships, memberships)
         |> assign(:invitations, invitations)
         |> assign(:is_owner, is_owner)
         |> assign(:github_connection, github_connection)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "You do not have access to this workspace")
         |> redirect(to: ~p"/preferences")}
    end
  end

  defp load_github_connection(workspace_id, actor) do
    case Integrations.get_workspace_github_connection(workspace_id,
           tenant: workspace_id,
           actor: actor,
           not_found_error?: false
         ) do
      {:ok, connection} -> connection
      {:error, _} -> nil
    end
  end

  defp load_workspace_data(workspace_id, current_user) do
    workspace =
      Accounts.get_workspace_by_id!(
        workspace_id,
        actor: current_user,
        load: [:owner]
      )

    memberships =
      Accounts.list_workspace_members!(
        query: [filter: [workspace_id: workspace.id]],
        actor: current_user,
        load: [:user]
      )

    invitations =
      Accounts.list_workspace_invitations!(
        query: [filter: [workspace_id: workspace.id, is_accepted: false]],
        actor: current_user,
        load: [:invited_by]
      )

    {:ok, workspace, memberships, invitations}
  rescue
    Ash.Error.Forbidden ->
      {:error, :forbidden}

    Ash.Error.Query.NotFound ->
      {:error, :not_found}

    Ash.Error.Invalid ->
      {:error, :not_found}
  end

  def handle_event("show-invite-modal", _params, socket) do
    {:noreply, assign(socket, :show_invite_modal, true)}
  end

  def handle_event("hide-invite-modal", _params, socket) do
    {:noreply, assign(socket, :show_invite_modal, false)}
  end

  def handle_event("show-leave-confirmation", _params, socket) do
    {:noreply, assign(socket, :show_leave_confirmation, true)}
  end

  def handle_event("hide-leave-confirmation", _params, socket) do
    {:noreply, assign(socket, :show_leave_confirmation, false)}
  end

  def handle_event("confirm-leave-workspace", _params, socket) do
    current_user = socket.assigns.current_user
    workspace = socket.assigns.workspace

    # Find the current user's membership
    memberships =
      Accounts.list_workspace_members!(
        actor: current_user,
        query: [filter: [workspace_id: workspace.id, user_id: current_user.id]]
      )

    case memberships do
      [membership] ->
        case Accounts.remove_workspace_member!(membership, actor: current_user) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "You have left the workspace")
             |> redirect(to: ~p"/preferences")}

          {:error, _error} ->
            {:noreply,
             socket
             |> assign(:show_leave_confirmation, false)
             |> put_flash(:error, "Failed to leave workspace")}
        end

      [] ->
        {:noreply,
         socket
         |> assign(:show_leave_confirmation, false)
         |> put_flash(:error, "Membership not found")}
    end
  end

  def handle_event("cancel-leave-workspace", _, socket) do
    {:noreply, assign(socket, :show_leave_confirmation, false)}
  end

  def handle_event("remove-member", %{"id" => membership_id}, socket) do
    # Get the membership
    [membership] =
      Accounts.list_workspace_members!(
        actor: socket.assigns.current_user,
        query: [filter: [id: membership_id]],
        load: [:user]
      )

    case Accounts.remove_workspace_member!(membership, actor: socket.assigns.current_user) do
      :ok ->
        # Reload memberships
        memberships =
          Accounts.list_workspace_members!(
            query: [filter: [workspace_id: socket.assigns.workspace.id]],
            actor: socket.assigns.current_user,
            load: [:user]
          )

        {:noreply,
         socket
         |> assign(:memberships, memberships)
         |> put_flash(:info, "Member removed successfully")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to remove member")}
    end
  end

  def handle_event("revoke-invitation", %{"id" => invitation_id}, socket) do
    # Get the invitation
    [invitation] =
      Accounts.list_workspace_invitations!(
        actor: socket.assigns.current_user,
        query: [filter: [id: invitation_id]]
      )

    case Accounts.revoke_invitation!(invitation, actor: socket.assigns.current_user) do
      :ok ->
        # Reload invitations
        invitations =
          Accounts.list_workspace_invitations!(
            query: [
              filter: [workspace_id: socket.assigns.workspace.id, is_accepted: false]
            ],
            actor: socket.assigns.current_user,
            load: [:invited_by]
          )

        {:noreply,
         socket
         |> assign(:invitations, invitations)
         |> put_flash(:info, "Invitation revoked successfully")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke invitation")}
    end
  end

  def handle_event("show-github-modal", _params, socket) do
    {:noreply, assign(socket, :show_github_modal, true)}
  end

  def handle_event("show-disconnect-confirmation", _params, socket) do
    {:noreply, assign(socket, :show_disconnect_confirmation, true)}
  end

  def handle_event("cancel-disconnect-github", _params, socket) do
    {:noreply, assign(socket, :show_disconnect_confirmation, false)}
  end

  def handle_event("confirm-disconnect-github", _params, socket) do
    connection = socket.assigns.github_connection
    actor = socket.assigns.current_user

    case Integrations.delete_github_connection(connection, actor: actor) do
      :ok ->
        {:noreply,
         socket
         |> assign(:github_connection, nil)
         |> assign(:show_disconnect_confirmation, false)
         |> put_flash(:info, "GitHub disconnected successfully")}

      {:error, _error} ->
        {:noreply,
         socket
         |> assign(:show_disconnect_confirmation, false)
         |> put_flash(:error, "Failed to disconnect GitHub")}
    end
  end

  def handle_info({:invitation_sent, _invitation}, socket) do
    # Reload invitations
    invitations =
      Accounts.list_workspace_invitations!(
        query: [filter: [workspace_id: socket.assigns.workspace.id, is_accepted: false]],
        actor: socket.assigns.current_user,
        load: [:invited_by]
      )

    {:noreply,
     socket
     |> assign(:invitations, invitations)
     |> assign(:show_invite_modal, false)
     |> put_flash(:info, "Invitation sent successfully")}
  end

  def handle_info(:close_github_modal, socket) do
    {:noreply, assign(socket, :show_github_modal, false)}
  end

  def handle_info({:github_connected, connection}, socket) do
    {:noreply,
     socket
     |> assign(:github_connection, connection)
     |> assign(:show_github_modal, false)
     |> put_flash(:info, "GitHub connected successfully")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_workspace={@current_workspace} workspaces={@workspaces}>
      <div class="flex justify-between items-center mb-4">
        <h1 class="text-2xl">Workspace: {@workspace.name}</h1>
        <div class="flex gap-2">
          <.link :if={@is_owner} navigate={~p"/preferences/workspaces/#{@workspace.id}/edit"}>
            <.button variant="ghost">Edit Workspace</.button>
          </.link>
          <.button :if={!@is_owner} variant="error" phx-click="show-leave-confirmation">
            Leave Workspace
          </.button>
        </div>
      </div>

      <div class="space-y-6">
        <.card class="bg-base-200 border-base-300">
          <:title>Members</:title>
          <.table id="members" rows={@memberships}>
            <:col :let={membership} label="Email">
              {membership.user.email}
            </:col>
            <:col :let={membership} label="Role">
              <%= if membership.user_id == @workspace.owner_id do %>
                Owner
              <% else %>
                Member
              <% end %>
            </:col>
            <:action :let={membership}>
              <.button
                :if={@is_owner && membership.user_id != @workspace.owner_id}
                phx-click="remove-member"
                phx-value-id={membership.id}
                data-confirm="Are you sure you want to remove this member?"
              >
                Remove
              </.button>
            </:action>
          </.table>
        </.card>

        <.card class="bg-base-200 border-base-300">
          <:title>
            <span class="mr-4">
              Pending Invitations
            </span>
            <.button :if={@is_owner} variant="primary" phx-click="show-invite-modal">
              Invite Member
            </.button>
          </:title>

          <.table id="invitations" rows={@invitations}>
            <:col :let={invitation} label="Email">
              {invitation.email}
            </:col>
            <:col :let={invitation} label="Invited By">
              {invitation.invited_by.email}
            </:col>
            <:col :let={invitation} label="Expires At">
              {Calendar.strftime(invitation.expires_at, "%Y-%m-%d %H:%M")}
            </:col>
            <:action :let={invitation}>
              <.button
                :if={@is_owner}
                phx-click="revoke-invitation"
                phx-value-id={invitation.id}
                data-confirm="Are you sure you want to revoke this invitation?"
              >
                Revoke
              </.button>
            </:action>
          </.table>
        </.card>

        <.card class="bg-base-200 border-base-300">
          <:title>Integrations</:title>
          <div class="flex items-center justify-between py-2">
            <div class="flex items-center gap-3">
              <div class="bg-base-300 rounded-lg p-2">
                <.icon name="hero-code-bracket" class="h-6 w-6" />
              </div>
              <div>
                <h4 class="font-medium">GitHub</h4>
                <p class="text-sm text-base-content/70">
                  <%= if @github_connection do %>
                    Connected — allows chat agents to inspect your repositories
                  <% else %>
                    Not connected
                  <% end %>
                </p>
              </div>
            </div>

            <%= if @github_connection do %>
              <.button
                :if={@is_owner}
                variant="error"
                phx-click="show-disconnect-confirmation"
              >
                Disconnect
              </.button>
              <span :if={!@is_owner} class="badge badge-success">Connected</span>
            <% else %>
              <.button :if={@is_owner} variant="primary" phx-click="show-github-modal">
                Connect
              </.button>
              <span :if={!@is_owner} class="badge badge-ghost">Not connected</span>
            <% end %>
          </div>
        </.card>
      </div>

      <.live_component
        :if={@show_invite_modal}
        module={CitadelWeb.Components.InviteMemberModal}
        id="invite-member-modal"
        current_user={@current_user}
        workspace={@workspace}
      />

      <.live_component
        :if={@show_leave_confirmation}
        module={CitadelWeb.Components.ConfirmationModal}
        id="leave-workspace-modal"
        title="Leave Workspace"
        message="Are you sure you want to leave this workspace? You will lose access to all conversations and tasks in this workspace."
        confirm_label="Leave Workspace"
        cancel_label="Cancel"
        on_confirm="confirm-leave-workspace"
        on_cancel="cancel-leave-workspace"
      />

      <.live_component
        :if={@show_github_modal}
        module={CitadelWeb.Components.GitHubConnectionModal}
        id="github-connection-modal"
        workspace={@workspace}
        current_user={@current_user}
      />

      <.live_component
        :if={@show_disconnect_confirmation}
        module={CitadelWeb.Components.ConfirmationModal}
        id="disconnect-github-modal"
        title="Disconnect GitHub"
        message="Are you sure you want to disconnect GitHub? Chat agents will no longer be able to access your repositories."
        confirm_label="Disconnect"
        cancel_label="Cancel"
        on_confirm="confirm-disconnect-github"
        on_cancel="cancel-disconnect-github"
      />
    </Layouts.app>
    """
  end
end
