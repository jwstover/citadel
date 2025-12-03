defmodule CitadelWeb.PreferencesLive.ApiKeyNew do
  @moduledoc false

  use CitadelWeb, :live_view

  alias Citadel.Accounts.ApiKey

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
  on_mount {CitadelWeb.LiveUserAuth, :load_workspace}

  def mount(_params, _session, socket) do
    form =
      AshPhoenix.Form.for_create(ApiKey, :create,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id,
        prepare_source: fn changeset ->
          changeset
          |> Ash.Changeset.change_attribute(:user_id, socket.assigns.current_user.id)
          |> Ash.Changeset.change_attribute(:workspace_id, socket.assigns.current_workspace.id)
        end,
        transform_params: fn params, _meta ->
          case params["expires_at"] do
            "" ->
              params

            date_string when is_binary(date_string) ->
              {:ok, date} = Date.from_iso8601(date_string)
              datetime = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
              Map.put(params, "expires_at", datetime)

            _ ->
              params
          end
        end
      )
      |> to_form()

    {:ok,
     socket
     |> assign(:form, form)
     |> assign(:created_api_key, nil)
     |> assign(:plaintext_key, nil)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form,
           params: params,
           action_opts: [
             actor: socket.assigns.current_user,
             tenant: socket.assigns.current_workspace.id
           ]
         ) do
      {:ok, api_key} ->
        plaintext_key = api_key.__metadata__.plaintext_api_key

        {:noreply,
         socket
         |> assign(:created_api_key, api_key)
         |> assign(:plaintext_key, plaintext_key)}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/preferences")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_workspace={@current_workspace} workspaces={@workspaces}>
      <div class="max-w-2xl mx-auto">
        <h1 class="text-2xl font-bold mb-6">New API Key</h1>

        <%= if @created_api_key do %>
          <.card class="bg-base-200 border-base-300">
            <:title>API Key Created</:title>

            <div class="space-y-4">
              <div class="alert alert-warning">
                <.icon name="hero-exclamation-triangle" class="size-5" />
                <span>
                  Make sure to copy your API key now. You won't be able to see it again!
                </span>
              </div>

              <div>
                <label class="label mb-1">API Key</label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    readonly
                    value={@plaintext_key}
                    class="input w-full font-mono text-sm"
                    id="api-key-value"
                  />
                  <button
                    type="button"
                    class="btn btn-neutral"
                    phx-hook="Clipboard"
                    id="copy-api-key"
                    data-clipboard-target="#api-key-value"
                  >
                    <.icon name="hero-clipboard-document" class="size-5" /> Copy
                  </button>
                </div>
              </div>

              <div class="flex justify-end">
                <.link navigate={~p"/preferences"}>
                  <.button variant="primary">Done</.button>
                </.link>
              </div>
            </div>
          </.card>
        <% else %>
          <.card class="bg-base-200 border-base-300">
            <:title>Create API Key</:title>

            <div class="alert alert-info mb-4">
              <.icon name="hero-information-circle" class="size-5" />
              <span>
                This API key will be scoped to the <strong>{@current_workspace.name}</strong>
                workspace.
              </span>
            </div>

            <.form for={@form} phx-submit="save" class="space-y-4" id="api-key-form">
              <.input
                field={@form[:name]}
                label="Name"
                placeholder="e.g. Production Server, Development"
                required
              />

              <.input
                field={@form[:expires_at]}
                type="date"
                label="Expires At"
                required
              />

              <div class="flex gap-2 justify-end">
                <.button type="button" phx-click="cancel" variant="ghost">
                  Cancel
                </.button>
                <.button type="submit" variant="primary">
                  Create API Key
                </.button>
              </div>
            </.form>
          </.card>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
