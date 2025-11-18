defmodule CitadelWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use CitadelWeb, :verified_routes

  alias AshAuthentication.Phoenix.LiveSession

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {CitadelWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:load_workspace, _params, session, socket) do
    if socket.assigns[:current_user] do
      workspace_id =
        session["current_workspace_id"] || get_default_workspace_id(socket.assigns.current_user)

      workspace =
        Citadel.Accounts.get_workspace_by_id!(
          workspace_id,
          actor: socket.assigns.current_user
        )

      {:cont, assign(socket, :current_workspace, workspace)}
    else
      {:cont, socket}
    end
  end

  defp get_default_workspace_id(user) do
    workspaces = Citadel.Accounts.list_workspaces!(actor: user)
    List.first(workspaces).id
  end
end
