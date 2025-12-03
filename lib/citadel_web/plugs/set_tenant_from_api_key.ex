defmodule CitadelWeb.Plugs.SetTenantFromApiKey do
  @moduledoc """
  Sets the tenant (workspace_id) on the connection based on the authenticated API key.

  This plug runs AFTER AshAuthentication.Strategy.ApiKey.Plug and retrieves the
  workspace_id from the API key stored in the user's metadata.

  When a user authenticates via API key, AshAuthentication stores the API key
  record in `user.__metadata__.api_key`. This plug extracts the workspace_id
  from that record and sets it as the tenant for subsequent Ash operations.
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, api_key} <- get_api_key_from_metadata(user),
         {:ok, workspace_id} <- get_workspace_id(api_key) do
      Ash.PlugHelpers.set_tenant(conn, workspace_id)
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

  defp get_api_key_from_metadata(user) do
    case user.__metadata__[:api_key] do
      nil -> :error
      api_key -> {:ok, api_key}
    end
  end

  defp get_workspace_id(api_key) do
    case Map.get(api_key, :workspace_id) do
      nil -> :error
      workspace_id -> {:ok, workspace_id}
    end
  end
end
