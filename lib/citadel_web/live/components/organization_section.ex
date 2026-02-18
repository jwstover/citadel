defmodule CitadelWeb.Components.OrganizationSection do
  @moduledoc """
  LiveComponent for displaying and managing organization settings,
  including organization name and member management.
  """

  use CitadelWeb, :live_component

  alias Citadel.Accounts

  def update(assigns, socket) do
    organization_id = assigns.current_workspace.organization_id
    user = assigns.current_user

    organization =
      Accounts.get_organization_by_id!(organization_id, actor: user, load: [:memberships])

    memberships = get_memberships(organization_id, user)

    user_membership = Enum.find(memberships, &(&1.user_id == user.id))
    user_role = if user_membership, do: user_membership.role, else: nil
    can_manage = user_role in [:owner, :admin]

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:organization, organization)
     |> assign(:memberships, memberships)
     |> assign(:user_role, user_role)
     |> assign(:can_manage, can_manage)
     |> assign(:editing_name, false)
     |> assign(:confirm_remove_id, nil)
     |> assign_name_form(organization)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.card class="bg-base-200 border-base-300">
        <:title>
          <div class="flex justify-between items-center w-full">
            <span>Organization</span>
          </div>
        </:title>

        <div class="space-y-6">
          <div class="flex items-center justify-between">
            <%= if @editing_name do %>
              <.form
                for={@name_form}
                phx-submit="save-name"
                phx-target={@myself}
                class="flex items-center gap-2 flex-1"
              >
                <.input
                  field={@name_form[:name]}
                  type="text"
                  class="input input-sm input-bordered flex-1"
                  phx-mounted={JS.focus()}
                />
                <.button type="submit" variant="primary" class="btn-sm">Save</.button>
                <.button
                  type="button"
                  variant="ghost"
                  class="btn-sm"
                  phx-click="cancel-edit-name"
                  phx-target={@myself}
                >
                  Cancel
                </.button>
              </.form>
            <% else %>
              <div class="flex items-center gap-2">
                <h3 class="text-lg font-medium">{@organization.name}</h3>
                <button
                  :if={@can_manage}
                  class="btn btn-ghost btn-xs"
                  phx-click="edit-name"
                  phx-target={@myself}
                >
                  <.icon name="hero-pencil" class="h-4 w-4" />
                </button>
              </div>
            <% end %>
          </div>

          <div class="divider my-2"></div>

          <div>
            <h4 class="text-sm font-semibold mb-3">
              Members ({length(@memberships)})
            </h4>
            <.table id="org-members" rows={@memberships}>
              <:col :let={membership} label="Email">
                {membership.user.email}
              </:col>
              <:col :let={membership} label="Role">
                <span class={[
                  "badge",
                  membership.role == :owner && "badge-primary",
                  membership.role == :admin && "badge-secondary",
                  membership.role == :member && "badge-ghost"
                ]}>
                  {format_role(membership.role)}
                </span>
              </:col>
              <:action :let={membership}>
                <button
                  :if={
                    @can_manage && membership.role != :owner && membership.user_id != @current_user.id
                  }
                  class="btn btn-ghost btn-sm text-error"
                  phx-click="confirm-remove"
                  phx-value-id={membership.id}
                  phx-target={@myself}
                >
                  Remove
                </button>
              </:action>
            </.table>
          </div>
        </div>
      </.card>

      <.live_component
        :if={@confirm_remove_id}
        module={CitadelWeb.Components.ConfirmationModal}
        id="remove-member-modal"
        title="Remove Member"
        message="Are you sure you want to remove this member from the organization? They will lose access to all workspaces in this organization."
        confirm_label="Remove"
        cancel_label="Cancel"
        on_confirm="remove-member"
        on_cancel="cancel-remove"
        target={@myself}
      />
    </div>
    """
  end

  def handle_event("edit-name", _params, socket) do
    {:noreply, assign(socket, :editing_name, true)}
  end

  def handle_event("cancel-edit-name", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_name, false)
     |> assign_name_form(socket.assigns.organization)}
  end

  def handle_event("save-name", %{"organization" => params}, socket) do
    case Accounts.update_organization(socket.assigns.organization, params,
           actor: socket.assigns.current_user
         ) do
      {:ok, organization} ->
        {:noreply,
         socket
         |> assign(:organization, organization)
         |> assign(:editing_name, false)
         |> assign_name_form(organization)}

      {:error, changeset} ->
        {:noreply, assign(socket, :name_form, to_form(changeset))}
    end
  end

  def handle_event("confirm-remove", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_remove_id, id)}
  end

  def handle_event("cancel-remove", _params, socket) do
    {:noreply, assign(socket, :confirm_remove_id, nil)}
  end

  def handle_event("remove-member", _params, socket) do
    membership =
      Enum.find(socket.assigns.memberships, &(&1.id == socket.assigns.confirm_remove_id))

    case Accounts.remove_organization_member(membership, actor: socket.assigns.current_user) do
      :ok ->
        memberships =
          get_memberships(
            socket.assigns.organization.id,
            socket.assigns.current_user
          )

        {:noreply,
         socket
         |> assign(:memberships, memberships)
         |> assign(:confirm_remove_id, nil)}

      {:error, _} ->
        {:noreply, assign(socket, :confirm_remove_id, nil)}
    end
  end

  defp assign_name_form(socket, organization) do
    form =
      organization
      |> AshPhoenix.Form.for_update(:update,
        domain: Accounts,
        actor: socket.assigns.current_user,
        forms: [auto?: true]
      )
      |> to_form()

    assign(socket, :name_form, form)
  end

  defp get_memberships(organization_id, user) do
    Accounts.list_organization_members!(
      query: [filter: [organization_id: organization_id]],
      actor: user,
      load: [:user]
    )
  end

  defp format_role(:owner), do: "Owner"
  defp format_role(:admin), do: "Admin"
  defp format_role(:member), do: "Member"
  defp format_role(_), do: "Unknown"
end
