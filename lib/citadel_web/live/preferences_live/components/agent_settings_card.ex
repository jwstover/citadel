defmodule CitadelWeb.PreferencesLive.Components.AgentSettingsCard do
  @moduledoc false

  use CitadelWeb, :live_component

  require OpentelemetryPhoenixLiveViewProcessPropagator.LiveView, as: TracedLV
  require OpenTelemetry.Tracer, as: Tracer

  alias Citadel.Accounts
  alias Phoenix.LiveView.AsyncResult

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:workspace_async, AsyncResult.loading())
     |> assign(:form, nil)
     |> assign(:load_started?, false)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign(:workspace_id, assigns.workspace_id)
      |> assign(:current_user, assigns.current_user)
      |> assign(:is_owner, assigns.is_owner)
      |> maybe_start_load()

    {:ok, socket}
  end

  defp maybe_start_load(%{assigns: %{load_started?: true}} = socket), do: socket

  defp maybe_start_load(socket) do
    workspace_id = socket.assigns.workspace_id
    user = socket.assigns.current_user

    socket
    |> assign(:load_started?, true)
    |> TracedLV.start_async(:load_workspace, fn -> load_workspace(workspace_id, user) end)
  end

  @impl true
  def handle_async(:load_workspace, {:ok, {:ok, workspace}}, socket) do
    {:noreply,
     socket
     |> assign(:workspace_async, AsyncResult.ok(socket.assigns.workspace_async, workspace))
     |> assign(:form, build_form(workspace, socket.assigns.current_user, socket.assigns.is_owner))}
  end

  def handle_async(:load_workspace, {:ok, {:error, reason}}, socket),
    do:
      {:noreply,
       assign(
         socket,
         :workspace_async,
         AsyncResult.failed(socket.assigns.workspace_async, reason)
       )}

  def handle_async(:load_workspace, {:exit, reason}, socket),
    do:
      {:noreply,
       assign(
         socket,
         :workspace_async,
         AsyncResult.failed(socket.assigns.workspace_async, {:exit, reason})
       )}

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form,
           params: params,
           action_opts: [actor: socket.assigns.current_user]
         ) do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> assign(:workspace_async, AsyncResult.ok(socket.assigns.workspace_async, workspace))
         |> assign(
           :form,
           build_form(workspace, socket.assigns.current_user, socket.assigns.is_owner)
         )
         |> put_flash(:info, "Agent settings updated")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp build_form(_workspace, _user, false), do: nil

  defp build_form(workspace, user, true) do
    workspace
    |> AshPhoenix.Form.for_update(:update, actor: user)
    |> to_form()
  end

  defp load_workspace(workspace_id, user) do
    Tracer.with_span "agent_settings_card.load.workspace",
      attributes: %{"workspace.id" => workspace_id} do
      Accounts.get_workspace_by_id(workspace_id, actor: user)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.card class="bg-base-200 border-base-300">
        <:title>Agent Settings</:title>

        <.async_result :let={workspace} assign={@workspace_async}>
          <:loading>
            <div class="flex items-start justify-between gap-4 py-2">
              <div class="flex-1 min-w-0 space-y-2">
                <div class="skeleton h-4 w-48"></div>
                <div class="skeleton h-3 w-full"></div>
                <div class="skeleton h-3 w-3/4"></div>
              </div>
              <div class="skeleton h-9 w-32 shrink-0"></div>
            </div>
          </:loading>
          <:failed :let={_reason}>
            <p class="text-error text-sm italic">Failed to load agent settings.</p>
          </:failed>

          <div class="flex items-start justify-between gap-4 py-2">
            <div class="flex-1 min-w-0">
              <h4 class="font-medium">Max agent run duration</h4>
              <p class="text-sm text-base-content/70 mt-1">
                Hard wallclock cap on a single Claude Code run. Range 60&ndash;86400 seconds (default 14400 / 4 hours). Agents pick up changes on their next reconnect.
              </p>
            </div>

            <%= if @is_owner do %>
              <.form
                for={@form}
                id="agent-settings-form"
                phx-submit="save"
                phx-target={@myself}
                class="flex items-end gap-2 shrink-0"
              >
                <div>
                  <.input
                    field={@form[:agent_max_run_seconds]}
                    type="number"
                    label="Seconds"
                    min="60"
                    max="86400"
                    required
                  />
                </div>
                <.button type="submit" variant="primary">Save</.button>
              </.form>
            <% else %>
              <div class="shrink-0 text-right">
                <div class="text-lg font-semibold">{workspace.agent_max_run_seconds}s</div>
                <div class="text-xs text-base-content/60">read-only</div>
              </div>
            <% end %>
          </div>
        </.async_result>
      </.card>
    </div>
    """
  end
end
