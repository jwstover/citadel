defmodule CitadelWeb.Components.ApiKeysSection do
  @moduledoc """
  LiveComponent for managing API keys on the preferences page.
  """

  use CitadelWeb, :live_component

  alias Citadel.Accounts

  def update(assigns, socket) do
    api_keys = Accounts.list_api_keys!(actor: assigns.current_user, load: [:valid])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:api_keys, api_keys)
     |> assign(:confirm_revoke_id, nil)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.card class="bg-base-200 border-base-300">
        <:title>
          <div class="flex justify-between items-center w-full">
            <span>API Keys</span>
            <.link navigate={~p"/preferences/api-keys/new"}>
              <.button variant="primary">New API Key</.button>
            </.link>
          </div>
        </:title>

        <div :if={@api_keys == []} class="text-base-content/70 py-4">
          No API keys yet. Create one to access the API.
        </div>

        <.table :if={@api_keys != []} id="api-keys" rows={@api_keys}>
          <:col :let={api_key} label="Name">
            {api_key.name}
          </:col>
          <:col :let={api_key} label="Expires">
            {format_date(api_key.expires_at)}
          </:col>
          <:col :let={api_key} label="Status">
            <span class={[
              "badge",
              if(api_key.valid, do: "badge-success", else: "badge-error")
            ]}>
              {if api_key.valid, do: "Active", else: "Expired"}
            </span>
          </:col>
          <:action :let={api_key}>
            <button
              class="btn btn-ghost btn-sm text-error"
              phx-click="confirm_revoke"
              phx-value-id={api_key.id}
              phx-target={@myself}
            >
              Revoke
            </button>
          </:action>
        </.table>
      </.card>

      <.live_component
        :if={@confirm_revoke_id}
        module={CitadelWeb.Components.ConfirmationModal}
        id="revoke-api-key-modal"
        title="Revoke API Key"
        message="Are you sure you want to revoke this API key? This action cannot be undone and any applications using this key will lose access."
        confirm_label="Revoke"
        cancel_label="Cancel"
        on_confirm="revoke"
        on_cancel="cancel_revoke"
        target={@myself}
      />
    </div>
    """
  end

  def handle_event("confirm_revoke", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_revoke_id, id)}
  end

  def handle_event("cancel_revoke", _params, socket) do
    {:noreply, assign(socket, :confirm_revoke_id, nil)}
  end

  def handle_event("revoke", _params, socket) do
    api_key =
      Enum.find(socket.assigns.api_keys, &(&1.id == socket.assigns.confirm_revoke_id))

    case Accounts.destroy_api_key(api_key, actor: socket.assigns.current_user) do
      :ok ->
        api_keys =
          Accounts.list_api_keys!(actor: socket.assigns.current_user, load: [:valid])

        {:noreply,
         socket
         |> assign(:api_keys, api_keys)
         |> assign(:confirm_revoke_id, nil)}

      {:error, _} ->
        {:noreply, assign(socket, :confirm_revoke_id, nil)}
    end
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
end
