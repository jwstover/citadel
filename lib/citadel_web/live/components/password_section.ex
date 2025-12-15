defmodule CitadelWeb.Components.PasswordSection do
  @moduledoc """
  LiveComponent for managing password on the preferences page.
  Allows OAuth users to set a password and existing password users to change it.
  """

  use CitadelWeb, :live_component

  alias Citadel.Accounts

  def update(assigns, socket) do
    user = assigns.current_user
    has_password? = not is_nil(user.hashed_password)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:has_password?, has_password?)
     |> assign_form(has_password?)}
  end

  defp assign_form(socket, has_password?) do
    if has_password? do
      assign(
        socket,
        :form,
        to_form(%{"current_password" => "", "password" => "", "password_confirmation" => ""})
      )
    else
      assign(socket, :form, to_form(%{"password" => "", "password_confirmation" => ""}))
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <.card class="bg-base-200 border-base-300">
        <:title>
          <span>Password</span>
        </:title>

        <%= if @has_password? do %>
          <p class="text-sm text-base-content/70 mb-4">
            Change your password. You'll need to enter your current password to make changes.
          </p>

          <.form
            for={@form}
            phx-submit="change_password"
            phx-target={@myself}
            id="change-password-form"
          >
            <div class="space-y-4">
              <.input
                field={@form[:current_password]}
                type="password"
                label="Current Password"
                required
                autocomplete="current-password"
              />

              <.input
                field={@form[:password]}
                type="password"
                label="New Password"
                required
                autocomplete="new-password"
              />
              <p class="text-xs text-base-content/60 -mt-2">
                At least 8 characters with uppercase, lowercase, and a number.
              </p>

              <.input
                field={@form[:password_confirmation]}
                type="password"
                label="Confirm New Password"
                required
                autocomplete="new-password"
              />

              <.button type="submit" variant="primary">
                Change Password
              </.button>
            </div>
          </.form>
        <% else %>
          <p class="text-sm text-base-content/70 mb-4">
            You signed in with Google. Add a password to also sign in with email and password.
          </p>

          <.form for={@form} phx-submit="set_password" phx-target={@myself} id="set-password-form">
            <div class="space-y-4">
              <.input
                field={@form[:password]}
                type="password"
                label="Password"
                required
                autocomplete="new-password"
              />
              <p class="text-xs text-base-content/60 -mt-2">
                At least 8 characters with uppercase, lowercase, and a number.
              </p>

              <.input
                field={@form[:password_confirmation]}
                type="password"
                label="Confirm Password"
                required
                autocomplete="new-password"
              />

              <.button type="submit" variant="primary">
                Set Password
              </.button>
            </div>
          </.form>
        <% end %>
      </.card>
    </div>
    """
  end

  def handle_event(
        "set_password",
        %{"password" => password, "password_confirmation" => password_confirmation},
        socket
      ) do
    user = socket.assigns.current_user

    case Accounts.set_password(user, password, password_confirmation, actor: user) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:has_password?, true)
         |> assign_form(true)
         |> put_flash(:info, "Password set successfully!")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  def handle_event(
        "change_password",
        %{
          "current_password" => current_password,
          "password" => password,
          "password_confirmation" => password_confirmation
        },
        socket
      ) do
    user = socket.assigns.current_user

    case Accounts.change_password(user, current_password, password, password_confirmation,
           actor: user
         ) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign_form(true)
         |> put_flash(:info, "Password changed successfully!")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  defp format_errors(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _opts}} ->
      "#{field} #{msg}"
    end)
  end
end
