defmodule CitadelWeb.Components.InviteMemberModal do
  @moduledoc false

  use CitadelWeb, :live_component

  require Logger

  alias Citadel.Accounts.WorkspaceInvitation

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign_form()}
  end

  def handle_event("send-invitation", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form,
           params: params,
           action_opts: [
             actor: socket.assigns.current_user
           ]
         ) do
      {:ok, invitation} ->
        send(self(), {:invitation_sent, invitation})
        {:noreply, socket}

      {:error, form} ->
        Logger.error("Error creating invitation: #{inspect(form)}")
        {:noreply, socket |> assign(:form, form)}
    end
  end

  def assign_form(socket) do
    form =
      AshPhoenix.Form.for_create(WorkspaceInvitation, :create,
        actor: socket.assigns.current_user,
        prepare_params: fn params, _context ->
          Map.put(params, "workspace_id", socket.assigns.workspace.id)
        end
      )
      |> to_form()

    socket
    |> assign(:form, form)
  end

  def render(assigns) do
    ~H"""
    <dialog id={@id} class="modal modal-open">
      <div class="modal-box" phx-click-away="hide-invite-modal">
        <form method="dialog">
          <button
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
            phx-click="hide-invite-modal"
          >
            ✕
          </button>
        </form>
        <h3 class="text-lg font-bold mb-2">Invite Member</h3>

        <.form for={@form} phx-submit="send-invitation" phx-target={@myself}>
          <.input field={@form[:email]} placeholder="Email" type="email" />
          <.button variant="primary" type="submit">Send Invitation</.button>
        </.form>
      </div>
    </dialog>
    """
  end
end
