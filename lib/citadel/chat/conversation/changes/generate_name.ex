defmodule Citadel.Chat.Conversation.Changes.GenerateName do
  @moduledoc """
  Generates an AI-powered title for conversations based on message history.

  Uses the configured AI provider to analyze conversation content and
  create a concise, descriptive title (2-8 words).
  """
  use Ash.Resource.Change
  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      conversation = changeset.data

      opts = Ash.Context.to_opts(context)

      messages =
        Citadel.Chat.Message
        |> Ash.Query.filter(conversation_id == ^conversation.id)
        |> Ash.Query.limit(10)
        |> Ash.Query.select([:id, :text, :source])
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.read!(Keyword.put(opts, :authorize?, false))
        |> Enum.reverse()

      prompt = build_prompt(messages)
      actor = context.actor

      case Citadel.AI.send_message(prompt, actor, tools: false) do
        {:ok, title} ->
          Ash.Changeset.force_change_attribute(changeset, :title, String.trim(title))

        {:error, type, message} ->
          Ash.Changeset.add_error(changeset, "Failed to generate conversation name: #{type} - #{message}")
      end
    end)
  end

  defp build_prompt(messages) do
    message_history =
      messages
      |> Enum.map_join("\n", fn msg ->
        role = if msg.source == :agent, do: "Assistant", else: "User"
        "#{role}: #{msg.text}"
      end)

    """
    Based on this conversation, provide a short name/title for it.
    2-8 words, preferring more succinct names.
    RESPOND WITH ONLY THE NEW CONVERSATION NAME, nothing else.

    Conversation:
    #{message_history}
    """
  end
end
