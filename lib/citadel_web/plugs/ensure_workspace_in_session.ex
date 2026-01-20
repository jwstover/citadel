defmodule CitadelWeb.Plugs.EnsureWorkspaceInSession do
  @moduledoc """
  Ensures every authenticated request has a valid workspace_id in the session.

  This plug runs after authentication and checks if current_workspace_id exists
  in the session. If missing, it loads the user's first workspace and sets it.

  This ensures that both LiveView routes (which run on_mount hooks) and regular
  controller routes (which don't) have a consistent workspace_id available in
  the session.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, workspace_id} <- get_or_set_workspace_id(conn, user) do
      put_session(conn, "current_workspace_id", workspace_id)
    else
      _ -> conn
    end
  end

  defp get_current_user(conn) do
    case conn.assigns[:current_user] do
      nil -> :error
      user -> {:ok, user}
    end
  end

  defp get_or_set_workspace_id(conn, user) do
    case get_session(conn, "current_workspace_id") do
      nil -> load_default_workspace_id(user)
      workspace_id -> {:ok, workspace_id}
    end
  end

  defp load_default_workspace_id(user) do
    case Citadel.Accounts.list_workspaces!(actor: user) do
      [] -> :error
      workspaces -> {:ok, List.first(workspaces).id}
    end
  end
end
