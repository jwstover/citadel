defmodule CitadelWeb.ChatLive do
  use Elixir.CitadelWeb, :live_view
  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
  on_mount {CitadelWeb.LiveUserAuth, :load_workspace}
  on_mount {CitadelWeb.LiveUserAuth, :require_ai_chat_feature}

  import CitadelWeb.Components.Markdown

  def render(assigns) do
    ~H"""
    <div class="drawer md:drawer-open bg-base-200 min-h-dvh max-h-dvh">
      <input id="ash-ai-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content flex flex-col">
        <div class="navbar bg-base-300 w-full">
          <div class="flex-none md:hidden">
            <label for="ash-ai-drawer" aria-label="open sidebar" class="btn btn-square btn-ghost">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                class="inline-block h-6 w-6 stroke-current"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 6h16M4 12h16M4 18h16"
                >
                </path>
              </svg>
            </label>
          </div>
          <img
            src="https://github.com/ash-project/ash_ai/blob/main/logos/ash_ai.png?raw=true"
            alt="Logo"
            class="h-12"
            height="48"
          />
          <div class="mx-2 flex-1 px-2">
            <p :if={@conversation}>{build_conversation_title_string(@conversation.title)}</p>
            <p class="text-xs">AshAi</p>
          </div>
        </div>
        <div class="flex-1 flex flex-col overflow-y-scroll bg-base-200 max-h-[calc(100dvh-8rem)]">
          <div
            id="message-container"
            phx-update="stream"
            class="flex-1 overflow-y-auto px-4 py-2 flex flex-col-reverse"
          >
            <%= for {id, message} <- @streams.messages do %>
              <div
                id={id}
                class={[
                  "chat",
                  message.source == :user && "chat-end",
                  message.source == :agent && "chat-start"
                ]}
              >
                <div :if={message.source == :agent} class="chat-image avatar">
                  <div class="w-10 rounded-full bg-base-300 p-1">
                    <img
                      src="https://github.com/ash-project/ash_ai/blob/main/logos/ash_ai.png?raw=true"
                      alt="Logo"
                    />
                  </div>
                </div>
                <div :if={message.source == :user} class="chat-image avatar avatar-placeholder">
                  <div class="w-10 rounded-full bg-base-300">
                    <.icon name="hero-user-solid" class="block" />
                  </div>
                </div>
                <div class="chat-bubble">
                  {to_markdown(message.text)}
                </div>
              </div>
            <% end %>
            <div :if={@streaming_message} id="streaming-message" class="chat chat-start">
              <div class="chat-image avatar">
                <div class="w-10 rounded-full bg-base-300 p-1">
                  <img
                    src="https://github.com/ash-project/ash_ai/blob/main/logos/ash_ai.png?raw=true"
                    alt="Logo"
                  />
                </div>
              </div>
              <div class="chat-bubble">
                {to_markdown(@streaming_message.text)}
              </div>
            </div>
          </div>
        </div>
        <div class="p-4 border-t h-16">
          <.form
            :let={form}
            for={@message_form}
            phx-change="validate_message"
            phx-debounce="blur"
            phx-submit="send_message"
            class="flex items-center gap-4"
          >
            <div class="flex-1">
              <textarea
                name={form[:text].name}
                value={form[:text].value}
                type="textarea"
                phx-mounted={JS.focus()}
                placeholder="Type your message..."
                class="textarea textarea-primary w-full mb-0"
                autocomplete="off"
              />
            </div>
            <button type="submit" class="btn btn-primary rounded-full">
              <.icon name="hero-paper-airplane" /> Send
            </button>
          </.form>
        </div>
      </div>

      <div class="drawer-side border-r bg-base-300 min-w-72">
        <div class="py-4 px-6">
          <div class="text-lg mb-4">
            Conversations
          </div>
          <div class="mb-4">
            <.link navigate={~p"/chat"} class="btn btn-primary btn-lg mb-2">
              <div class="rounded-full bg-primary-content text-primary w-6 h-6 flex items-center justify-center">
                <.icon name="hero-plus" />
              </div>
              <span>New Chat</span>
            </.link>
          </div>
          <ul class="flex flex-col-reverse" phx-update="stream" id="conversations-list">
            <%= for {id, conversation} <- @streams.conversations do %>
              <li id={id}>
                <.link
                  navigate={~p"/chat/#{conversation.id}"}
                  phx-click="select_conversation"
                  phx-value-id={conversation.id}
                  class={"block py-2 px-3 transition border-l-4 pl-2 mb-2 #{if @conversation && @conversation.id == conversation.id, do: "border-primary font-medium", else: "border-transparent"}"}
                >
                  {build_conversation_title_string(conversation.title)}
                </.link>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  def build_conversation_title_string(title) do
    cond do
      title == nil -> "Untitled conversation"
      is_binary(title) && String.length(title) > 25 -> String.slice(title, 0, 25) <> "..."
      is_binary(title) && String.length(title) <= 25 -> title
    end
  end

  def mount(_params, _session, socket) do
    socket = assign_new(socket, :current_user, fn -> nil end)

    # Subscribe to workspace-scoped conversation updates
    CitadelWeb.Endpoint.subscribe("chat:conversations:#{socket.assigns.current_workspace.id}")

    socket =
      socket
      |> assign(:page_title, "Chat")
      |> assign(:streaming_message, nil)
      |> stream(
        :conversations,
        Citadel.Chat.my_conversations!(
          actor: socket.assigns.current_user,
          tenant: socket.assigns.current_workspace.id
        )
      )
      |> assign(:messages, [])

    {:ok, socket}
  end

  def handle_params(%{"conversation_id" => conversation_id}, _, socket) do
    conversation =
      Citadel.Chat.get_conversation!(conversation_id,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )

    cond do
      socket.assigns[:conversation] && socket.assigns[:conversation].id == conversation.id ->
        :ok

      socket.assigns[:conversation] ->
        # Switch subscriptions when changing conversations
        CitadelWeb.Endpoint.unsubscribe("chat:messages:#{socket.assigns.conversation.id}")
        CitadelWeb.Endpoint.unsubscribe("chat:stream:#{socket.assigns.conversation.id}")
        CitadelWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")
        CitadelWeb.Endpoint.subscribe("chat:stream:#{conversation.id}")

      true ->
        # Subscribe to message and stream updates for the selected conversation
        CitadelWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")
        CitadelWeb.Endpoint.subscribe("chat:stream:#{conversation.id}")
    end

    socket
    |> assign(:conversation, conversation)
    |> assign(:streaming_message, nil)
    |> stream(
      :messages,
      Citadel.Chat.message_history!(conversation.id,
        stream?: true,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.current_workspace.id
      )
    )
    |> assign_message_form()
    |> then(&{:noreply, &1})
  end

  def handle_params(_, _, socket) do
    if socket.assigns[:conversation] do
      CitadelWeb.Endpoint.unsubscribe("chat:messages:#{socket.assigns.conversation.id}")
      CitadelWeb.Endpoint.unsubscribe("chat:stream:#{socket.assigns.conversation.id}")
    end

    socket
    |> assign(:conversation, nil)
    |> assign(:streaming_message, nil)
    |> stream(:messages, [])
    |> assign_message_form()
    |> then(&{:noreply, &1})
  end

  def handle_event("validate_message", %{"form" => params}, socket) do
    {:noreply,
     assign(socket, :message_form, AshPhoenix.Form.validate(socket.assigns.message_form, params))}
  end

  def handle_event("send_message", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.message_form, params: params) do
      {:ok, message} ->
        # Check if AI is available before proceeding
        socket =
          if Citadel.AI.available?() do
            socket
          else
            put_flash(
              socket,
              :warning,
              "AI provider not configured. Your message was saved but no response will be generated."
            )
          end

        if socket.assigns.conversation do
          socket
          |> assign_message_form()
          |> stream_insert(:messages, message, at: 0)
          |> then(&{:noreply, &1})
        else
          {:noreply,
           socket
           |> push_navigate(to: ~p"/chat/#{message.conversation_id}")}
        end

      {:error, form} ->
        {:noreply, assign(socket, :message_form, form)}
    end
  end

  # Handle streaming deltas - accumulate text in streaming_message assign
  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "chat:stream:" <> _conversation_id,
          event: "delta",
          payload: %{message_id: message_id, content: content}
        },
        socket
      ) do
    streaming = socket.assigns.streaming_message || %{id: message_id, text: "", source: :agent}

    updated_streaming = %{streaming | text: streaming.text <> content}

    {:noreply, assign(socket, :streaming_message, updated_streaming)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "chat:stream:" <> _conversation_id,
          event: "complete"
        },
        socket
      ) do
    {:noreply, assign(socket, :streaming_message, nil)}
  end

  # Handle complete messages - clear streaming state and insert into stream
  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "chat:messages:" <> conversation_id,
          payload: message
        },
        socket
      ) do
    if socket.assigns.conversation && socket.assigns.conversation.id == conversation_id do
      socket =
        if socket.assigns.streaming_message &&
             socket.assigns.streaming_message.id == message.id do
          assign(socket, :streaming_message, nil)
        else
          socket
        end

      {:noreply, stream_insert(socket, :messages, message, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "chat:conversations:" <> _,
          payload: conversation
        },
        socket
      ) do
    socket =
      if socket.assigns.conversation && socket.assigns.conversation.id == conversation.id do
        assign(socket, :conversation, conversation)
      else
        socket
      end

    {:noreply, stream_insert(socket, :conversations, conversation)}
  end

  defp assign_message_form(socket) do
    form =
      if socket.assigns.conversation do
        Citadel.Chat.form_to_create_message(
          actor: socket.assigns.current_user,
          tenant: socket.assigns.current_workspace.id,
          prepare_params: fn params, _context ->
            Map.put(params, "conversation_id", socket.assigns.conversation.id)
          end
        )
        |> to_form()
      else
        Citadel.Chat.form_to_create_message(
          actor: socket.assigns.current_user,
          tenant: socket.assigns.current_workspace.id
        )
        |> to_form()
      end

    assign(
      socket,
      :message_form,
      form
    )
  end
end
