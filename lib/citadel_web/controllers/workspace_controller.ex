defmodule CitadelWeb.WorkspaceController do
  @moduledoc """
  Controller for workspace session management operations like switching workspaces.
  """

  use CitadelWeb, :controller

  def switch(conn, %{"workspace_id" => workspace_id}) do
    conn
    |> put_session("current_workspace_id", workspace_id)
    |> put_flash(:info, "Switched workspace")
    |> redirect(to: ~p"/")
  end
end
