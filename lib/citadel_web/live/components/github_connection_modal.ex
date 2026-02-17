defmodule CitadelWeb.Components.GitHubConnectionModal do
  @moduledoc """
  A modal component for connecting a GitHub account via Personal Access Token.
  """

  use CitadelWeb, :live_component

  alias Citadel.Integrations

  def render(assigns) do
    ~H"""
    <dialog id={@id} class="modal modal-open">
      <div class="modal-box" phx-click-away="close_modal" phx-target={@myself}>
        <form method="dialog">
          <button
            type="button"
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
            phx-click="close_modal"
            phx-target={@myself}
          >
            ✕
          </button>
        </form>

        <h3 class="text-lg font-bold mb-4">Connect GitHub</h3>

        <p class="text-sm text-base-content/70 mb-4">
          Enter a GitHub Personal Access Token to allow chat agents to inspect your repositories.
        </p>

        <.form for={@form} phx-submit="save_token" phx-target={@myself}>
          <.input
            field={@form[:pat]}
            type="password"
            label="Personal Access Token"
            placeholder="ghp_xxxxxxxxxxxxxxxxxxxx"
            autocomplete="off"
          />

          <details class="mt-4 text-sm">
            <summary class="cursor-pointer text-primary hover:underline">
              How to create a token
            </summary>
            <ol class="mt-2 text-base-content/70 list-decimal list-inside space-y-1 pl-2">
              <li>Go to GitHub Settings → Developer settings → Personal access tokens</li>
              <li>Click "Generate new token (classic)"</li>
              <li>
                Select scopes: <code class="bg-base-300 px-1 rounded">repo</code>
                (for private repos) or <code class="bg-base-300 px-1 rounded">public_repo</code>
                (for public only)
              </li>
              <li>
                Copy the generated token (starts with <code class="bg-base-300 px-1 rounded">ghp_</code>)
              </li>
            </ol>
          </details>

          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="close_modal" phx-target={@myself}>
              Cancel
            </button>
            <button type="submit" class="btn btn-primary" phx-disable-with="Connecting...">
              Connect
            </button>
          </div>
        </.form>
      </div>
    </dialog>
    """
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn -> to_form(%{"pat" => ""}) end)}
  end

  def handle_event("close_modal", _, socket) do
    send(self(), :close_github_modal)
    {:noreply, socket}
  end

  def handle_event("save_token", %{"pat" => pat}, socket) do
    workspace = socket.assigns.workspace
    actor = socket.assigns.current_user

    case Integrations.create_github_connection(pat, tenant: workspace.id, actor: actor) do
      {:ok, connection} ->
        send(self(), {:github_connected, connection})
        {:noreply, socket}

      {:error, %Ash.Error.Invalid{} = error} ->
        errors = get_error_messages(error)

        {:noreply,
         socket
         |> assign(:form, to_form(%{"pat" => pat}, errors: [pat: errors]))}

      {:error, _error} ->
        {:noreply,
         socket
         |> assign(:form, to_form(%{"pat" => pat}, errors: [pat: ["Failed to save token"]]))}
    end
  end

  defp get_error_messages(%Ash.Error.Invalid{errors: errors}) do
    Enum.flat_map(errors, fn
      %{message: message} when is_binary(message) -> [message]
      _ -> ["Invalid token"]
    end)
  end
end
