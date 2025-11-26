defmodule CitadelWeb.Components.ConfirmationModal do
  @moduledoc """
  A reusable confirmation modal component for destructive actions.
  """

  use CitadelWeb, :live_component

  def render(assigns) do
    ~H"""
    <dialog id={@id} class="modal modal-open">
      <div class="modal-box" phx-click-away={@on_cancel}>
        <form method="dialog">
          <button
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
            phx-click={@on_cancel}
            phx-target={@myself}
          >
            ✕
          </button>
        </form>

        <h3 class="text-lg font-bold mb-4">{@title}</h3>
        <p class="mb-6">{@message}</p>

        <div class="flex gap-2 justify-end">
          <button class="btn btn-ghost" phx-click={@on_cancel} phx-target={@myself}>
            {@cancel_label}
          </button>
          <button class="btn btn-error" phx-click={@on_confirm} phx-target={@myself}>
            {@confirm_label}
          </button>
        </div>
      </div>
    </dialog>
    """
  end

  def handle_event("cancel", _params, socket) do
    send(self(), {:cancel_confirmation, socket.assigns.id})
    {:noreply, socket}
  end

  def handle_event("confirm", _params, socket) do
    send(self(), {:confirm_action, socket.assigns.id})
    {:noreply, socket}
  end
end
