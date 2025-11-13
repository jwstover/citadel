defmodule Citadel.Chat.Conversation.Changes.GenerateName do
  @moduledoc """
  Generates an AI-powered title for conversations based on message history.

  Uses the configured AI provider to analyze conversation content and
  create a concise, descriptive title (2-8 words).
  """
  use Ash.Resource.Change
  require Ash.Query

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      conversation = changeset.data

      messages =
        Citadel.Chat.Message
        |> Ash.Query.filter(conversation_id == ^conversation.id)
        |> Ash.Query.limit(10)
        |> Ash.Query.select([:text, :source])
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.read!(actor: context.actor)

      system_prompt =
        LangChain.Message.new_system!("""
        Provide a short name for the current conversation.
        2-8 words, preferring more succinct names.
        RESPOND WITH ONLY THE NEW CONVERSATION NAME.
        """)

      message_chain = Enum.map(messages, &convert_to_langchain_message/1)

      %{
        llm: ChatOpenAI.new!(%{model: "gpt-4o"}),
        custom_context: Map.new(Ash.Context.to_opts(context)),
        verbose?: false
      }
      |> LLMChain.new!()
      |> LLMChain.add_message(system_prompt)
      |> LLMChain.add_messages(message_chain)
      |> LLMChain.run()
      |> case do
        {:ok,
         %LangChain.Chains.LLMChain{
           last_message: %{content: content}
         }} ->
          Ash.Changeset.force_change_attribute(changeset, :title, String.trim(content))

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  defp convert_to_langchain_message(%{source: :agent, text: text}) do
    LangChain.Message.new_assistant!(text)
  end

  defp convert_to_langchain_message(%{text: text}) do
    LangChain.Message.new_user!(text)
  end
end
