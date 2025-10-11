defmodule CitadelWeb.ChatLive.Index do
  @moduledoc """
  LiveView for AI-powered chat interface to interact with tasks.
  """
  use CitadelWeb, :live_view

  # AI client is now abstracted through Citadel.AI

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:messages, [])
      |> assign(:loading, false)

    {:ok, socket}
  end

  def handle_event("send_message", %{"message" => message_text}, socket) do
    if String.trim(message_text) == "" do
      {:noreply, socket}
    else
      # Add user message to the chat
      user_message = %{role: :user, content: message_text, id: generate_id()}
      messages = socket.assigns.messages ++ [user_message]

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:loading, true)
        |> clear_flash()

      # Send message to AI asynchronously
      send(self(), {:process_message, message_text})

      {:noreply, socket}
    end
  end

  def handle_info({:process_message, message_text}, socket) do
    case Citadel.AI.send_message(message_text, socket.assigns.current_user) do
      {:ok, response} ->
        assistant_message = %{role: :assistant, content: response, id: generate_id()}
        messages = socket.assigns.messages ++ [assistant_message]

        IO.inspect(messages, label: "================== MESSAGES\n")

        socket =
          socket
          |> assign(:messages, messages)
          |> assign(:loading, false)
          |> clear_flash()

        {:noreply, socket}

      {:error, error_type, message} ->
        socket =
          socket
          |> assign(:loading, false)
          |> put_flash(:error, Citadel.AI.format_error(error_type, message))

        {:noreply, socket}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col h-[calc(100vh-8rem)]">
        <%!-- Header --%>
        <div class="bg-base-200 p-4 border-b border-base-300">
          <h1 class="text-2xl font-bold">AI Task Assistant</h1>
          <p class="text-sm text-base-content/70">
            Chat with AI to manage your tasks. Try asking "What tasks do I have?" or "Create a task to review the quarterly report"
          </p>
        </div>

        <%!-- Chat Messages --%>
        <div class="flex-1 overflow-y-auto p-4 space-y-4" id="messages-container">
          <div :for={message <- @messages} class={["chat", message_class(message.role)]}>
            <div class="chat-bubble">
              {message.content}
            </div>
          </div>

          <div :if={@loading} class="chat chat-start">
            <div class="chat-bubble">
              <span class="loading loading-dots loading-sm"></span>
            </div>
          </div>
        </div>

        <%!-- Input Form --%>
        <div class="bg-base-200 p-4 border-t border-base-300">
          <form phx-submit="send_message" class="flex gap-2">
            <input
              type="text"
              name="message"
              placeholder="Type your message..."
              class="input input-bordered flex-1"
              autofocus
              disabled={@loading}
            />
            <button type="submit" class="btn btn-primary" disabled={@loading}>
              <span :if={!@loading}>Send</span>
              <span :if={@loading} class="loading loading-spinner"></span>
            </button>
          </form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp message_class(:user), do: "chat-end"
  defp message_class(:assistant), do: "chat-start"
end
