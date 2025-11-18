defmodule Citadel.Chat.Message.Changes.Respond do
  @moduledoc """
  Generates AI responses to user messages using the configured AI provider.

  This change handles streaming responses, tool calling, and conversation
  history management for chat interactions.
  """
  use Ash.Resource.Change
  require Ash.Query

  alias LangChain.Chains.LLMChain
  alias LangChain.Message.ToolCall
  alias LangChain.Message.ToolResult

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      message = changeset.data
      messages = fetch_conversation_messages(message, context)
      new_message_id = Ash.UUID.generate()

      messages
      |> setup_llm_chain(context, message, new_message_id)
      |> LLMChain.run(mode: :while_needs_response)

      changeset
    end)
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
  defp setup_llm_chain(messages, context, message, new_message_id) do
    system_prompt = build_system_prompt()
    message_chain = message_chain(messages)

    {:ok, chain} = create_configured_chain(context)

    chain
    |> LLMChain.add_message(system_prompt)
    |> LLMChain.add_messages(message_chain)
    |> add_callbacks(message, new_message_id, context)
  end

  defp build_system_prompt do
    LangChain.Message.new_system!("""
    You are a helpful chat bot.
    Your job is to use the tools at your disposal to assist the user.
    """)
  end

  defp create_configured_chain(context) do
    Citadel.AI.create_chain(context.actor,
      stream: true,
      setup_ash_ai: true,
      ash_ai_opts: [
        otp_app: :citadel
        # add the names of tools you want available in your conversation here.
        # i.e tools: [:list_tasks, :create_task]
        # tools: []
      ],
      custom_context: Map.new(Ash.Context.to_opts(context))
    )
  end

  defp add_callbacks(chain, message, message_id, context) do
    LLMChain.add_callback(chain, %{
      on_llm_new_delta: &handle_llm_delta(&1, &2, message_id, message, context),
      on_message_processed: &handle_message_processed(&1, &2, message_id, message, context)
    })
  end

  # Callback handlers
  defp handle_llm_delta(_model, data, message_id, message, context) do
    if has_content?(data) do
      upsert_message_response(message_id, message, data.content, %{}, context)
    end
  end

  defp handle_message_processed(_chain, data, message_id, message, context) do
    if should_persist_message?(data) do
      upsert_message_response(
        message_id,
        message,
        data.content || "",
        %{
          complete: true,
          tool_calls: transform_tool_calls(data.tool_calls),
          tool_results: transform_tool_results(data.tool_results)
        },
        context
      )
    end
  end

  # Message persistence
  defp upsert_message_response(id, message, text, additional_attrs, context) do
    base_attrs = %{
      id: id,
      response_to_id: message.id,
      conversation_id: message.conversation_id,
      text: text
    }

    context_opts = Ash.Context.to_opts(context)

    Citadel.Chat.Message
    |> Ash.Changeset.for_create(
      :upsert_response,
      Map.merge(base_attrs, additional_attrs),
      Keyword.merge([actor: %AshAi{}], context_opts)
    )
    |> Ash.create!()
  end

  # Condition helpers
  defp has_content?(data), do: data.content && data.content != ""

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
    Map.take(tool_result, [
      :type,
      :tool_call_id,
      :name,
      :content,
      :display_text,
      :is_error,
      :options
    ])
  end

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
