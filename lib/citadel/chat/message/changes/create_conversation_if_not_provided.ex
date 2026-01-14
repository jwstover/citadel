defmodule Citadel.Chat.Message.Changes.CreateConversationIfNotProvided do
  @moduledoc """
  Creates a conversation if one is not provided when creating a message.

  This ensures every message belongs to a conversation, automatically
  creating one if needed while validating permissions.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    if changeset.arguments[:conversation_id] do
      # Validate that the conversation exists and belongs to the actor
      Ash.Changeset.before_action(changeset, fn changeset ->
        validate_conversation(changeset, context)
      end)
    else
      Ash.Changeset.before_action(changeset, fn changeset ->
        opts = Ash.Context.to_opts(context) ++ [tenant: changeset.tenant]

        conversation =
          Citadel.Chat.create_conversation!(%{workspace_id: changeset.tenant}, opts)

        Ash.Changeset.force_change_attribute(changeset, :conversation_id, conversation.id)
      end)
    end
  end

  defp validate_conversation(changeset, context) do
    conversation_id = changeset.arguments.conversation_id
    opts = Ash.Context.to_opts(context) ++ [tenant: changeset.tenant]

    case Citadel.Chat.get_conversation(conversation_id, opts) do
      {:ok, _conversation} ->
        # Conversation exists and actor has access to it
        Ash.Changeset.force_change_attribute(changeset, :conversation_id, conversation_id)

      {:error, %Ash.Error.Forbidden{}} ->
        # Actor doesn't have access to this conversation
        Ash.Changeset.add_error(
          changeset,
          field: :conversation_id,
          message: "You don't have permission to add messages to this conversation"
        )

      {:error, %Ash.Error.Query.NotFound{}} ->
        # Conversation doesn't exist
        Ash.Changeset.add_error(
          changeset,
          field: :conversation_id,
          message: "Conversation not found"
        )

      {:error, _error} ->
        # Other error
        Ash.Changeset.add_error(
          changeset,
          field: :conversation_id,
          message: "Invalid conversation"
        )
    end
  end
end
