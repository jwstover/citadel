defmodule CitadelWeb.PreferencesLive.Workspace do
  @moduledoc false

  use CitadelWeb, :live_view

  alias Citadel.Accounts

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :show_invite_modal, false)}
  end

  def handle_params(%{"id" => workspace_id}, _uri, socket) do
    current_user = socket.assigns.current_user

    # Try to load workspace - will fail if user doesn't have access
    case load_workspace_data(workspace_id, current_user) do
      {:ok, workspace, memberships, invitations} ->
        is_owner = workspace.owner_id == current_user.id

        {:noreply,
         socket
         |> assign(:workspace, workspace)
         |> assign(:memberships, memberships)
         |> assign(:invitations, invitations)
         |> assign(:is_owner, is_owner)
         |> assign(:current_workspace, workspace)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "You do not have access to this workspace")
         |> redirect(to: ~p"/preferences")}
    end
  end

  defp load_workspace_data(workspace_id, current_user) do
    try do
      # Load workspace with owner - will raise if user doesn't have access
      workspace =
        Accounts.get_workspace_by_id!(
          workspace_id,
          actor: current_user,
          load: [:owner]
        )

      # Load memberships with user details
      memberships =
        Accounts.list_workspace_members!(
          query: [filter: [workspace_id: workspace.id]],
          actor: current_user,
          load: [:user]
        )

      # Filter pending invitations (not accepted)
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
  end

  def handle_event("show-invite-modal", _params, socket) do
    {:noreply, assign(socket, :show_invite_modal, true)}
  end

  def handle_event("hide-invite-modal", _params, socket) do
    {:noreply, assign(socket, :show_invite_modal, false)}
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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl mb-4">Workspace Management</h1>

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
      </div>

      <.live_component
        :if={@show_invite_modal}
        module={CitadelWeb.Components.InviteMemberModal}
        id="invite-member-modal"
        current_user={@current_user}
        current_workspace={@current_workspace}
      />
    </Layouts.app>
    """
  end
end
