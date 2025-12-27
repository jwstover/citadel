defmodule CitadelWeb.PreferencesLive.WorkspaceForm do
  @moduledoc false

  use CitadelWeb, :live_view

  alias Citadel.Accounts
  alias Citadel.Accounts.Workspace

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
  on_mount {CitadelWeb.LiveUserAuth, :load_workspace}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :new ->
        {:noreply, assign_new_form(socket)}

      :edit ->
        handle_edit_params(params, socket)
    end
  end

  defp handle_edit_params(%{"id" => workspace_id}, socket) do
    current_user = socket.assigns.current_user

    case load_workspace_for_edit(workspace_id, current_user) do
      {:ok, workspace} ->
        {:noreply, assign_edit_form(socket, workspace)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "You do not have permission to edit this workspace")
         |> redirect(to: ~p"/preferences")}
    end
  end

  defp load_workspace_for_edit(workspace_id, current_user) do
    workspace =
      Accounts.get_workspace_by_id!(workspace_id, actor: current_user)

    # Verify user is owner
    if workspace.owner_id == current_user.id do
      {:ok, workspace}
    else
      {:error, :forbidden}
    end
  rescue
    Ash.Error.Forbidden ->
      {:error, :forbidden}

    Ash.Error.Query.NotFound ->
      {:error, :not_found}

    Ash.Error.Invalid ->
      {:error, :not_found}
  end

  defp assign_new_form(socket) do
    current_user = socket.assigns.current_user

    # Get user's first organization to use for new workspaces
    organizations = Accounts.list_organizations!(actor: current_user)
    organization_id = List.first(organizations) && List.first(organizations).id

    form =
      AshPhoenix.Form.for_create(Workspace, :create,
        actor: current_user,
        params: %{"organization_id" => organization_id}
      )
      |> to_form()

    socket
    |> assign(:form, form)
    |> assign(:workspace, nil)
    |> assign(:organization_id, organization_id)
    |> assign(:page_title, "New Workspace")
  end

  defp assign_edit_form(socket, workspace) do
    form =
      AshPhoenix.Form.for_update(workspace, :update, actor: socket.assigns.current_user)
      |> to_form()

    socket
    |> assign(:form, form)
    |> assign(:workspace, workspace)
    |> assign(:page_title, "Edit Workspace")
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form,
           params: params,
           action_opts: [actor: socket.assigns.current_user]
         ) do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> put_flash(:info, workspace_saved_message(socket.assigns.live_action))
         |> redirect(to: ~p"/preferences/workspace/#{workspace.id}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  def handle_event("cancel", _params, socket) do
    path =
      case socket.assigns.workspace do
        nil -> ~p"/preferences"
        workspace -> ~p"/preferences/workspace/#{workspace.id}"
      end

    {:noreply, redirect(socket, to: path)}
  end

  defp workspace_saved_message(:new), do: "Workspace created successfully"
  defp workspace_saved_message(:edit), do: "Workspace updated successfully"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_workspace={@current_workspace} workspaces={@workspaces}>
      <div class="max-w-2xl mx-auto">
        <h1 class="text-2xl font-bold mb-6">{@page_title}</h1>

        <.card class="bg-base-200 border-base-300">
          <:title>{@page_title}</:title>
          <.form for={@form} phx-submit="save" class="space-y-4">
            <input
              :if={assigns[:organization_id]}
              type="hidden"
              name="form[organization_id]"
              value={@organization_id}
            />
            <.input
              field={@form[:name]}
              label="Workspace Name"
              placeholder="e.g. My Team, Personal, Work Projects"
              required
            />

            <div class="flex gap-2 justify-end">
              <.button type="button" phx-click="cancel" variant="ghost">
                Cancel
              </.button>
              <.button type="submit" variant="primary">
                {if @workspace, do: "Update Workspace", else: "Create Workspace"}
              </.button>
            </div>
          </.form>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
