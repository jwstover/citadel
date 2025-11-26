defmodule CitadelWeb.InvitationLive.Accept do
  @moduledoc """
  Public page for accepting workspace invitations via token.
  """

  use CitadelWeb, :live_view

  alias Citadel.Accounts

  on_mount {CitadelWeb.LiveUserAuth, :live_user_optional}

  def mount(%{"token" => token}, _session, socket) do
    case load_invitation(token) do
      {:ok, invitation} ->
        {:ok,
         socket
         |> assign(:invitation, invitation)
         |> assign(:token, token)
         |> assign(:error, nil)}

      {:error, reason} ->
        {:ok,
         socket
         |> assign(:invitation, nil)
         |> assign(:token, token)
         |> assign(:error, reason)}
    end
  end

  defp load_invitation(token) do
    case Accounts.get_invitation_by_token(token, load: [:workspace, :invited_by, :is_accepted, :is_expired], authorize?: false) do
      {:ok, invitation} ->
        cond do
          invitation.is_accepted ->
            {:error, :already_accepted}

          invitation.is_expired ->
            {:error, :expired}

          true ->
            {:ok, invitation}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  rescue
    _ ->
      {:error, :not_found}
  end

  def handle_event("accept", _params, socket) do
    case socket.assigns.current_user do
      nil ->
        # Not logged in - redirect to sign in with return path
        {:noreply,
         redirect(socket,
           to: ~p"/sign-in?return_to=#{~p"/invitations/#{socket.assigns.token}"}"
         )}

      user ->
        # Logged in - accept the invitation
        accept_invitation(socket, user)
    end
  end

  defp accept_invitation(socket, user) do
    invitation = socket.assigns.invitation

    case Accounts.accept_invitation!(invitation, actor: user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Welcome to #{invitation.workspace.name}!")
         |> redirect(to: ~p"/preferences/workspace/#{invitation.workspace.id}")}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to accept invitation. You may already be a member.")
         |> assign(:error, :accept_failed)}
    end
  rescue
    _ ->
      {:noreply,
       socket
       |> put_flash(:error, "An error occurred while accepting the invitation.")
       |> assign(:error, :accept_failed)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-2xl mx-auto mt-8">
        <%= if @error do %>
          <.card class="bg-base-200 border-base-300">
            <:title>Invitation Error</:title>
            <div class="text-center py-8">
              <.icon name="hero-exclamation-circle" class="h-16 w-16 mx-auto text-error mb-4" />
              <h2 class="text-2xl font-bold mb-2">{error_title(@error)}</h2>
              <p class="text-base-content/70 mb-6">{error_message(@error)}</p>
              <.link navigate={~p"/"}>
                <.button variant="primary">Go Home</.button>
              </.link>
            </div>
          </.card>
        <% else %>
          <.card class="bg-base-200 border-base-300">
            <:title>Workspace Invitation</:title>
            <div class="text-center py-8">
              <.icon name="hero-envelope" class="h-16 w-16 mx-auto text-primary mb-4" />
              <h2 class="text-2xl font-bold mb-2">Workspace Invitation</h2>

              <div class="space-y-4 my-6">
                <p class="text-lg">
                  You've been invited to join
                  <strong class="font-semibold">{@invitation.workspace.name}</strong>
                </p>
                <p class="text-base-content/70">
                  Invited by <strong>{@invitation.invited_by.email}</strong>
                </p>
                <p class="text-sm text-base-content/60">
                  Expires: {Calendar.strftime(@invitation.expires_at, "%B %d, %Y at %I:%M %p")}
                </p>
              </div>

              <%= if @current_user do %>
                <div class="space-y-4">
                  <p class="text-base-content/80">
                    Accepting as <strong>{@current_user.email}</strong>
                  </p>
                  <.button variant="primary" phx-click="accept" class="btn-lg">
                    Accept Invitation
                  </.button>
                </div>
              <% else %>
                <div class="space-y-4">
                  <p class="text-base-content/80">
                    Sign in to accept this invitation
                  </p>
                  <.link navigate={~p"/sign-in?return_to=#{~p"/invitations/#{@token}"}"}>
                    <.button variant="primary" class="btn-lg">Sign In to Accept</.button>
                  </.link>
                </div>
              <% end %>
            </div>
          </.card>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp error_title(:not_found), do: "Invitation Not Found"
  defp error_title(:expired), do: "Invitation Expired"
  defp error_title(:already_accepted), do: "Invitation Already Accepted"
  defp error_title(:accept_failed), do: "Failed to Accept"

  defp error_message(:not_found) do
    "This invitation link is invalid or has been revoked. Please contact the workspace owner for a new invitation."
  end

  defp error_message(:expired) do
    "This invitation has expired. Please contact the workspace owner for a new invitation."
  end

  defp error_message(:already_accepted) do
    "This invitation has already been accepted. You should already have access to the workspace."
  end

  defp error_message(:accept_failed) do
    "Unable to accept this invitation. You may already be a member of this workspace, or there may be another issue. Please try again or contact support."
  end
end
