defmodule Citadel.Chat.Message.Changes.Respond do
  @moduledoc """
  Generates AI responses to user messages using the configured AI provider.

  This change handles streaming responses, tool calling, and conversation
  history management for chat interactions. When a workspace has a GitHub
  connection configured, GitHub MCP tools are automatically included.
  """
  use Ash.Resource.Change
  require Ash.Query
  require Logger

  alias Citadel.MCP.ClientManager
  alias LangChain.Chains.LLMChain
  alias LangChain.Message.ToolCall
  alias LangChain.Message.ToolResult

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      message = changeset.data

      try do
        run_response_generation(message, context)
      rescue
        e ->
          Logger.error("""
          AI response generation failed for message #{message.id}:
          #{Exception.format(:error, e, __STACKTRACE__)}
          """)
      catch
        kind, reason ->
          Logger.error("""
          AI response generation failed for message #{message.id}:
          #{inspect(kind)}: #{inspect(reason)}
          """)
      end

      changeset
    end)
  end

  defp run_response_generation(message, context) do
    messages = fetch_conversation_messages(message, context)
    new_message_id = Ash.UUIDv7.generate()
    workspace_id = get_workspace_id(message, context)
    github_tools = get_github_tools(workspace_id)

    case setup_llm_chain(messages, context, message, new_message_id, github_tools) do
      {:ok, chain} ->
        case LLMChain.run(chain, mode: :while_needs_response) do
          {:ok, _updated_chain} ->
            :ok

          {:error, %LLMChain{}, %LangChain.LangChainError{} = error} ->
            Logger.error("LLMChain.run failed for message #{message.id}: #{error.message}")

            :error

          {:error, %LLMChain{} = _chain} ->
            Logger.error("LLMChain.run failed for message #{message.id}: unknown error")
            :error

          other ->
            Logger.error(
              "Unexpected response from LLMChain.run for message #{message.id}: #{inspect(other)}"
            )

            :error
        end

      {:error, reason} ->
        Logger.warning("Skipping AI response for message #{message.id}: #{inspect(reason)}")

        :skipped
    end
  end

  defp get_workspace_id(message, context) do
    case Ash.Context.to_opts(context)[:tenant] do
      nil ->
        conversation =
          Citadel.Chat.Conversation
          |> Ash.Query.filter(id == ^message.conversation_id)
          |> Ash.Query.select([:workspace_id])
          |> Ash.read_one!(authorize?: false)

        conversation && conversation.workspace_id

      tenant_id ->
        tenant_id
    end
  end

  defp get_github_tools(nil), do: []

  defp get_github_tools(workspace_id) do
    case ClientManager.get_tools(workspace_id) do
      {:ok, tools} ->
        Logger.debug("Loaded #{length(tools)} GitHub MCP tools for workspace #{workspace_id}")
        tools

      {:error, :no_connection} ->
        []

      {:error, reason} ->
        Logger.warning(
          "Failed to load GitHub tools for workspace #{workspace_id}: #{inspect(reason)}"
        )

        []
    end
  end

  # Message fetching
  defp fetch_conversation_messages(message, context) do
    Citadel.Chat.Message
    |> Ash.Query.filter(conversation_id == ^message.conversation_id)
    |> Ash.Query.filter(id != ^message.id)
    |> Ash.Query.select([:text, :source, :tool_calls, :tool_results])
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(Ash.Context.to_opts(context))
    |> Enum.concat([%{source: :user, text: message.text}])
  end

  # Chain setup
  defp setup_llm_chain(messages, context, message, new_message_id, github_tools) do
    case create_configured_chain(context) do
      {:ok, chain} ->
        has_github_tools = github_tools != []
        system_prompt = build_system_prompt(has_github_tools)
        message_chain = message_chain(messages)

        configured_chain =
          chain
          |> LLMChain.add_message(system_prompt)
          |> LLMChain.add_messages(message_chain)
          |> maybe_add_github_tools(github_tools)
          |> add_callbacks(message, new_message_id, context)

        {:ok, configured_chain}

      {:error, :provider_not_configured, reason} ->
        {:error, {:provider_not_configured, reason}}

      {:error, _type, reason} ->
        {:error, {:chain_creation_failed, reason}}
    end
  end

  defp maybe_add_github_tools(chain, []), do: chain

  defp maybe_add_github_tools(chain, github_tools) do
    LLMChain.add_tools(chain, github_tools)
  end

  defp build_system_prompt(has_github_tools) do
    base_prompt = """
    You are a helpful chat bot.
    Your job is to use the tools at your disposal to assist the user.
    """

    if has_github_tools do
      LangChain.Message.new_system!(
        base_prompt <>
          """

          You have access to GitHub tools that allow you to interact with the user's connected repositories:
          - Search code across repositories
          - Read file contents from repositories
          - View commit history
          - Search for repositories
          - And more

          Use these tools when the user asks about their codebase, wants to find code, or needs help with their repositories.
          """
      )
    else
      LangChain.Message.new_system!(base_prompt)
    end
  end

  defp create_configured_chain(context) do
    context_opts = Ash.Context.to_opts(context)

    Citadel.AI.create_chain(context.actor,
      stream: true,
      setup_ash_ai: true,
      ash_ai_opts: [
        otp_app: :citadel,
        tenant: context_opts[:tenant]
      ],
      custom_context: Map.new(context_opts)
    )
  end

  defp add_callbacks(chain, message, message_id, context) do
    LLMChain.add_callback(chain, %{
      on_llm_new_delta: &handle_llm_delta(&1, &2, message_id, message, context),
      on_message_processed: &handle_message_processed(&1, &2, message_id, message, context)
    })
  end

  # Callback handlers
  defp handle_llm_delta(_model, deltas, message_id, message, _context) when is_list(deltas) do
    content = extract_delta_content(deltas)

    if content && content != "" do
      broadcast_stream_delta(message.conversation_id, message_id, content)
    end
  end

  defp handle_llm_delta(_model, data, message_id, message, _context) do
    if has_content?(data) do
      broadcast_stream_delta(message.conversation_id, message_id, extract_content(data.content))
    end
  end

  defp broadcast_stream_delta(conversation_id, message_id, content) do
    CitadelWeb.Endpoint.broadcast(
      "chat:stream:#{conversation_id}",
      "delta",
      %{message_id: message_id, content: content}
    )
  end

  defp extract_delta_content(deltas) do
    deltas
    |> Enum.map(fn delta -> extract_content(delta.content) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("")
  end

  defp extract_content(%LangChain.Message.ContentPart{type: :text, content: content}), do: content
  defp extract_content(content) when is_binary(content), do: content
  defp extract_content(_), do: nil

  defp handle_message_processed(_chain, data, message_id, message, context) do
    if should_persist_message?(data) do
      content = extract_message_content(data.content)

      create_message_response(
        message_id,
        message,
        content || "",
        %{
          tool_calls: transform_tool_calls(data.tool_calls),
          tool_results: transform_tool_results(data.tool_results)
        },
        context
      )
    end
  end

  defp extract_message_content(nil), do: nil
  defp extract_message_content(content) when is_binary(content), do: content

  defp extract_message_content(content) when is_list(content) do
    content
    |> Enum.map(&extract_content_part/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("")
  end

  defp extract_message_content(%LangChain.Message.ContentPart{} = part) do
    extract_content_part(part)
  end

  defp extract_message_content(_), do: nil

  defp extract_content_part(%LangChain.Message.ContentPart{type: :text, content: content}), do: content
  defp extract_content_part(%{"type" => "text", "text" => text}), do: text
  defp extract_content_part(_), do: nil

  # Message persistence
  defp create_message_response(id, message, text, additional_attrs, context) do
    base_attrs = %{
      id: id,
      response_to_id: message.id,
      conversation_id: message.conversation_id,
      text: text
    }

    context_opts = Ash.Context.to_opts(context)

    Citadel.Chat.Message
    |> Ash.Changeset.for_create(
      :create_response,
      Map.merge(base_attrs, additional_attrs),
      Keyword.merge([actor: %AshAi{}], context_opts)
    )
    |> Ash.create!()
  end

  # Condition helpers
  defp has_content?(%{content: content}) do
    extracted = extract_message_content(content)
    extracted && extracted != ""
  end

  defp has_content?(_), do: false

  defp should_persist_message?(data) do
    has_tool_calls?(data) || has_tool_results?(data) || has_content?(data)
  end

  defp has_tool_calls?(%{tool_calls: calls}) when is_list(calls), do: Enum.any?(calls)
  defp has_tool_calls?(_), do: false

  defp has_tool_results?(%{tool_results: results}) when is_list(results), do: Enum.any?(results)
  defp has_tool_results?(_), do: false

  # Tool call/result transformations
  defp transform_tool_calls(nil), do: nil

  defp transform_tool_calls(tool_calls) do
    Enum.map(tool_calls, &extract_tool_call_fields/1)
  end

  defp extract_tool_call_fields(tool_call) do
    Map.take(tool_call, [:status, :type, :call_id, :name, :arguments, :index])
  end

  defp transform_tool_results(nil), do: nil

  defp transform_tool_results(tool_results) do
    Enum.map(tool_results, &extract_tool_result_fields/1)
  end

  defp extract_tool_result_fields(tool_result) do
    tool_result
    |> Map.take([
      :type,
      :tool_call_id,
      :name,
      :content,
      :display_text,
      :is_error,
      :options
    ])
    |> Map.update(:content, nil, &normalize_tool_result_content/1)
  end

  defp normalize_tool_result_content(content) when is_list(content) do
    Enum.map(content, &normalize_content_part/1)
  end

  defp normalize_tool_result_content(content), do: content

  defp normalize_content_part(%LangChain.Message.ContentPart{} = part) do
    %{type: part.type, content: part.content}
  end

  defp normalize_content_part(other), do: other

  # Message chain conversion
  defp message_chain(messages) do
    Enum.flat_map(messages, &convert_message_to_langchain/1)
  end

  defp convert_message_to_langchain(%{source: :agent} = message) do
    langchain_message = build_assistant_message(message)

    if has_tool_results?(message) do
      [langchain_message, build_tool_result_message(message)]
    else
      [langchain_message]
    end
  end

  defp convert_message_to_langchain(%{source: :user, text: text}) do
    [LangChain.Message.new_user!(text)]
  end

  defp build_assistant_message(message) do
    LangChain.Message.new_assistant!(%{
      content: message.text,
      tool_calls: build_tool_calls(message.tool_calls)
    })
  end

  defp build_tool_calls(nil), do: nil

  defp build_tool_calls(tool_calls) do
    Enum.map(tool_calls, fn tool_call ->
      tool_call
      |> stringify_keys()
      |> Map.take(["status", "type", "call_id", "name", "arguments", "index"])
      |> ToolCall.new!()
    end)
  end

  defp build_tool_result_message(message) do
    LangChain.Message.new_tool_result!(%{
      tool_results: build_tool_results(message.tool_results)
    })
  end

  defp build_tool_results(tool_results) do
    Enum.map(tool_results, fn tool_result ->
      tool_result
      |> stringify_keys()
      |> Map.take([
        "type",
        "tool_call_id",
        "name",
        "content",
        "display_text",
        "is_error",
        "options"
      ])
      |> ToolResult.new!()
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
