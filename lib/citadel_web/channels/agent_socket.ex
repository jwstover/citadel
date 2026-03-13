defmodule CitadelWeb.AgentSocket do
  use Phoenix.Socket

  channel "agents:*", CitadelWeb.AgentChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case authenticate_api_key(token) do
      {:ok, user, workspace_id} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:workspace_id, workspace_id)

        {:ok, socket}

      :error ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "agent_socket:#{socket.assigns.workspace_id}"

  defp authenticate_api_key(token) do
    with {:ok, user} <- sign_in_with_api_key(token),
         {:ok, workspace_id} <- extract_workspace_id(user) do
      {:ok, user, workspace_id}
    else
      _ -> :error
    end
  end

  defp sign_in_with_api_key(token) do
    case Citadel.Accounts.User
         |> Ash.Query.for_read(:sign_in_with_api_key, %{api_key: token})
         |> Ash.read(authorize?: false) do
      {:ok, [user | _]} -> {:ok, user}
      _ -> :error
    end
  end

  defp extract_workspace_id(user) do
    case user.__metadata__[:api_key] do
      %{workspace_id: workspace_id} when not is_nil(workspace_id) ->
        {:ok, workspace_id}

      _ ->
        :error
    end
  end
end
