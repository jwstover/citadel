defmodule CitadelWeb.McpOAuthDiscoveryController do
  use CitadelWeb, :controller

  def not_found(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "not_found"}))
  end
end
