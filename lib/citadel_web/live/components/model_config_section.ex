defmodule CitadelWeb.Components.ModelConfigSection do
  @moduledoc false

  use CitadelWeb, :live_component

  require Logger

  alias Citadel.Tasks
  alias Citadel.Tasks.ModelConfig

  def update(assigns, socket) do
    model_configs =
      Tasks.list_model_configs!(
        tenant: assigns.workspace.id,
        actor: assigns.current_user
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:model_configs, model_configs)
     |> assign(:show_form, false)
     |> assign(:editing_id, nil)
     |> assign(:show_delete_confirmation, nil)
     |> assign(:form, nil)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.card class="bg-base-200 border-base-300">
        <:title>
          <div class="flex justify-between items-center w-full">
            <span>Model Configuration</span>
            <.button
              :if={!@show_form}
              variant="primary"
              class="btn-sm"
              phx-click="show-config-form"
              phx-target={@myself}
            >
              Add Configuration
            </.button>
          </div>
        </:title>

        <%= if @show_form do %>
          <div class="border border-base-300 rounded-lg p-4 mb-4">
            <h4 class="font-medium mb-3">
              {if @editing_id, do: "Edit Configuration", else: "New Configuration"}
            </h4>
            <.form
              for={@form}
              id="model-config-form"
              phx-submit="save-config"
              phx-change="validate-config"
              phx-target={@myself}
            >
              <div class="grid grid-cols-2 gap-4">
                <.input field={@form[:name]} label="Name" placeholder="e.g. Fast Draft" />
                <.input
                  field={@form[:provider]}
                  type="select"
                  label="Provider"
                  options={[Anthropic: :anthropic, OpenAI: :openai]}
                />
              </div>
              <div class="grid grid-cols-3 gap-4">
                <.input
                  field={@form[:model]}
                  label="Model"
                  placeholder="e.g. claude-sonnet-4-20250514"
                />
                <.input
                  field={@form[:temperature]}
                  type="number"
                  label="Temperature"
                  step="0.1"
                  min="0"
                  max="2"
                />
                <.input
                  field={@form[:max_tokens]}
                  type="number"
                  label="Max Tokens"
                  placeholder="Optional"
                />
              </div>
              <div class="flex gap-2 mt-2">
                <.button variant="primary" type="submit">
                  {if @editing_id, do: "Update", else: "Create"}
                </.button>
                <.button
                  type="button"
                  variant="ghost"
                  phx-click="cancel-config-form"
                  phx-target={@myself}
                >
                  Cancel
                </.button>
              </div>
            </.form>
          </div>
        <% end %>

        <%= if @model_configs == [] && !@show_form do %>
          <div class="text-center py-8 text-base-content/60">
            <.icon name="hero-cpu-chip" class="h-8 w-8 mx-auto mb-2 opacity-50" />
            <p>No model configurations yet.</p>
            <p class="text-sm">Agents will use system defaults.</p>
          </div>
        <% else %>
          <.table :if={@model_configs != []} id="model-configs" rows={@model_configs}>
            <:col :let={config} label="Name">
              <span class="font-medium">{config.name}</span>
            </:col>
            <:col :let={config} label="Provider">
              <span class={[
                "badge badge-sm",
                config.provider == :anthropic && "badge-secondary",
                config.provider == :openai && "badge-accent"
              ]}>
                {provider_label(config.provider)}
              </span>
            </:col>
            <:col :let={config} label="Model">
              <code class="text-sm">{config.model}</code>
            </:col>
            <:col :let={config} label="Temperature">
              {config.temperature}
            </:col>
            <:col :let={config} label="Default">
              <button
                phx-click="toggle-default"
                phx-value-id={config.id}
                phx-target={@myself}
                class="cursor-pointer"
              >
                <%= if config.is_default do %>
                  <.icon name="hero-star-solid" class="h-5 w-5 text-warning" />
                <% else %>
                  <.icon name="hero-star" class="h-5 w-5 text-base-content/30 hover:text-warning/60" />
                <% end %>
              </button>
            </:col>
            <:action :let={config}>
              <div class="flex gap-2">
                <button
                  class="btn btn-ghost btn-xs"
                  phx-click="edit-config"
                  phx-value-id={config.id}
                  phx-target={@myself}
                >
                  <.icon name="hero-pencil" class="h-4 w-4" />
                </button>
                <button
                  class="btn btn-ghost btn-xs text-error"
                  phx-click="confirm-delete-config"
                  phx-value-id={config.id}
                  phx-target={@myself}
                >
                  <.icon name="hero-trash" class="h-4 w-4" />
                </button>
              </div>
            </:action>
          </.table>
        <% end %>
      </.card>

      <.live_component
        :if={@show_delete_confirmation}
        module={CitadelWeb.Components.ConfirmationModal}
        id="delete-model-config-modal"
        title="Delete Model Configuration"
        message="Are you sure you want to delete this model configuration? Tasks referencing it will fall back to the workspace default."
        confirm_label="Delete"
        cancel_label="Cancel"
        on_confirm="delete-config"
        on_cancel="cancel-delete-config"
        target={@myself}
      />
    </div>
    """
  end

  def handle_event("show-config-form", _params, socket) do
    form = build_create_form(socket)

    {:noreply,
     socket |> assign(:show_form, true) |> assign(:editing_id, nil) |> assign(:form, form)}
  end

  def handle_event("cancel-config-form", _params, socket) do
    {:noreply,
     socket |> assign(:show_form, false) |> assign(:editing_id, nil) |> assign(:form, nil)}
  end

  def handle_event("validate-config", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save-config", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form,
           params: params,
           action_opts: [
             actor: socket.assigns.current_user,
             tenant: socket.assigns.workspace.id
           ]
         ) do
      {:ok, _config} ->
        model_configs = reload_configs(socket)

        {:noreply,
         socket
         |> assign(:model_configs, model_configs)
         |> assign(:show_form, false)
         |> assign(:editing_id, nil)
         |> assign(:form, nil)
         |> put_flash(
           :info,
           if(socket.assigns.editing_id,
             do: "Configuration updated",
             else: "Configuration created"
           )
         )}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("edit-config", %{"id" => id}, socket) do
    config = Enum.find(socket.assigns.model_configs, &(&1.id == id))

    form =
      AshPhoenix.Form.for_update(config, :update,
        domain: Tasks,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.workspace.id,
        forms: [auto?: true]
      )
      |> to_form()

    {:noreply,
     socket |> assign(:show_form, true) |> assign(:editing_id, id) |> assign(:form, form)}
  end

  def handle_event("confirm-delete-config", %{"id" => id}, socket) do
    {:noreply, assign(socket, :show_delete_confirmation, id)}
  end

  def handle_event("cancel-delete-config", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirmation, nil)}
  end

  def handle_event("delete-config", _params, socket) do
    config =
      Enum.find(socket.assigns.model_configs, &(&1.id == socket.assigns.show_delete_confirmation))

    case Tasks.destroy_model_config(config,
           actor: socket.assigns.current_user,
           tenant: socket.assigns.workspace.id
         ) do
      :ok ->
        model_configs = reload_configs(socket)

        {:noreply,
         socket
         |> assign(:model_configs, model_configs)
         |> assign(:show_delete_confirmation, nil)
         |> put_flash(:info, "Configuration deleted")}

      {:error, _error} ->
        {:noreply,
         socket
         |> assign(:show_delete_confirmation, nil)
         |> put_flash(:error, "Failed to delete configuration")}
    end
  end

  def handle_event("toggle-default", %{"id" => id}, socket) do
    config = Enum.find(socket.assigns.model_configs, &(&1.id == id))

    case Tasks.set_model_config_default(config,
           actor: socket.assigns.current_user,
           tenant: socket.assigns.workspace.id
         ) do
      {:ok, _config} ->
        model_configs = reload_configs(socket)

        {:noreply,
         socket
         |> assign(:model_configs, model_configs)
         |> put_flash(:info, "Default configuration updated")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to set default")}
    end
  end

  defp build_create_form(socket) do
    AshPhoenix.Form.for_create(ModelConfig, :create,
      domain: Tasks,
      actor: socket.assigns.current_user,
      tenant: socket.assigns.workspace.id,
      prepare_params: fn params, _context ->
        Map.put(params, "workspace_id", socket.assigns.workspace.id)
      end
    )
    |> to_form()
  end

  defp reload_configs(socket) do
    Tasks.list_model_configs!(
      tenant: socket.assigns.workspace.id,
      actor: socket.assigns.current_user
    )
  end

  defp provider_label(:anthropic), do: "Anthropic"
  defp provider_label(:openai), do: "OpenAI"
  defp provider_label(other), do: to_string(other)
end
