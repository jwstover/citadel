defmodule CitadelWeb.Components.ConfirmationModal do
  @moduledoc """
  A reusable confirmation modal component for destructive actions.
  """

  use CitadelWeb, :live_component

  def render(assigns) do
    ~H"""
    <dialog id={@id} class="modal modal-open">
      <div class="modal-box" phx-click-away={@on_cancel} phx-target={@target}>
        <form method="dialog">
          <button
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
            phx-click={@on_cancel}
            phx-target={@target}
          >
            ✕
          </button>
        </form>

        <h3 class="text-lg font-bold mb-4">{@title}</h3>
        <p class="mb-6">{@message}</p>

        <div class="flex gap-2 justify-end">
          <button class="btn btn-ghost" phx-click={@on_cancel} phx-target={@target}>
            {@cancel_label}
          </button>
          <button class="btn btn-error" phx-click={@on_confirm} phx-target={@target}>
            {@confirm_label}
          </button>
        </div>
      </div>
    </dialog>
    """
  end

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign_new(:target, fn -> nil end)}
  end
end
