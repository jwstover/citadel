defmodule Citadel.Chat.Message.Changes.CreateConversationIfNotProvided do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    if changeset.arguments[:conversation_id] do
      # Validate that the conversation exists and belongs to the actor
      Ash.Changeset.before_action(changeset, fn changeset ->
        conversation_id = changeset.arguments.conversation_id

        case Citadel.Chat.get_conversation(conversation_id, Ash.Context.to_opts(context)) do
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
      end)
    else
      Ash.Changeset.before_action(changeset, fn changeset ->
        conversation = Citadel.Chat.create_conversation!(Ash.Context.to_opts(context))

        Ash.Changeset.force_change_attribute(changeset, :conversation_id, conversation.id)
      end)
    end
  end
end
