defmodule CitadelWeb.McpOAuthDiscoveryController do
  use CitadelWeb, :controller

  def show(conn, _params) do
    base_url = CitadelWeb.Endpoint.url()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        resource: "#{base_url}/mcp",
        bearer_methods_supported: ["header"],
        resource_signing_alg_values_supported: []
      })
    )
  end
end
