defmodule Citadel.Chat.Message do
  @moduledoc """
  Represents a chat message from either a user or AI agent.

  Messages support streaming responses, tool calling, and automatic
  AI response generation through background jobs.

  Note: Messages inherit workspace context through their conversation relationship.
  No direct workspace_id is stored on messages; workspace scoping is handled
  via the conversation.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub],
    authorizers: [Ash.Policy.Authorizer]

  oban do
    triggers do
      trigger :respond do
        actor_persister Citadel.AiAgentActorPersister
        read_action :needs_response
        action :respond
        queue :chat_responses
        lock_for_update? false
        scheduler_cron false
        worker_module_name Citadel.Chat.Message.Workers.Respond
        scheduler_module_name Citadel.Chat.Message.Schedulers.Respond
        where expr(needs_response)
      end
    end
  end

  postgres do
    table "messages"
    repo Citadel.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :needs_response do
      multitenancy :allow_global
      pagination keyset?: true
      filter expr(needs_response)
    end

    read :for_conversation do
      pagination keyset?: true, required?: false
      argument :conversation_id, :uuid, allow_nil?: false

      prepare build(default_sort: [inserted_at: :desc])
      filter expr(conversation_id == ^arg(:conversation_id))
    end

    create :create do
      accept [:text]

      validate match(:text, ~r/\S/) do
        message "Message cannot be empty"
      end

      argument :conversation_id, :uuid do
        allow_nil? true
      end

      change Citadel.Chat.Message.Changes.CreateConversationIfNotProvided
      change run_oban_trigger(:respond)
    end

    update :respond do
      accept []
      require_atomic? false
      transaction? false
      change Citadel.Chat.Message.Changes.Respond
    end

    create :upsert_response do
      upsert? true
      accept [:id, :response_to_id, :conversation_id]
      argument :complete, :boolean, default: false
      argument :text, :string, allow_nil?: false, constraints: [trim?: false, allow_empty?: true]
      argument :tool_calls, {:array, :map}
      argument :tool_results, {:array, :map}

      # if updating
      #   if complete, set the text to the provided text
      #   if streaming still, add the text to the provided text
      change atomic_update(
               :text,
               {:atomic,
                expr(
                  if ^arg(:complete) do
                    ^arg(:text)
                  else
                    ^atomic_ref(:text) <> ^arg(:text)
                  end
                )}
             )

      change atomic_update(
               :tool_calls,
               {:atomic,
                expr(
                  if is_nil(^arg(:tool_calls)) do
                    ^atomic_ref(:tool_calls)
                  else
                    fragment(
                      "? || ?",
                      ^atomic_ref(:tool_calls),
                      type(
                        ^arg(:tool_calls),
                        {:array, :map}
                      )
                    )
                  end
                )}
             )

      change atomic_update(
               :tool_results,
               {:atomic,
                expr(
                  if is_nil(^arg(:tool_results)) do
                    ^atomic_ref(:tool_results)
                  else
                    fragment(
                      "? || ?",
                      ^atomic_ref(:tool_results),
                      type(
                        ^arg(:tool_results),
                        {:array, :map}
                      )
                    )
                  end
                )}
             )

      # if creating, set the text attribute to the provided text
      change set_attribute(:text, arg(:text))
      change set_attribute(:complete, arg(:complete))
      change set_attribute(:source, :agent)
      change set_attribute(:tool_results, arg(:tool_results))
      change set_attribute(:tool_calls, arg(:tool_calls))

      # on update, only set complete to its new value
      upsert_fields [:complete]
    end

    create :create_response do
      upsert? true
      upsert_identity :unique_id
      accept [:id, :response_to_id, :conversation_id, :text]
      argument :tool_calls, {:array, :map}
      argument :tool_results, {:array, :map}

      change set_attribute(:source, :agent)
      change set_attribute(:complete, true)
      change set_attribute(:tool_calls, arg(:tool_calls))
      change set_attribute(:tool_results, arg(:tool_results))

      upsert_fields [:text, :complete, :tool_calls, :tool_results]
    end
  end

  policies do
    # Allow AshAi actor (background jobs) full access for processing messages
    bypass actor_attribute_equals(:__struct__, AshAi) do
      authorize_if always()
    end

    policy action(:respond) do
      authorize_if expr(
                     conversation.workspace.owner_id == ^actor(:id) or
                       exists(conversation.workspace.memberships, user_id == ^actor(:id))
                   )
    end

    policy action(:for_conversation) do
      authorize_if expr(
                     conversation.workspace.owner_id == ^actor(:id) or
                       exists(conversation.workspace.memberships, user_id == ^actor(:id))
                   )
    end

    # Read: users can read messages in conversations within their workspace
    policy action_type(:read) do
      authorize_if expr(
                     conversation.workspace.owner_id == ^actor(:id) or
                       exists(conversation.workspace.memberships, user_id == ^actor(:id))
                   )
    end

    # Create: authenticated users can create messages
    # The CreateConversationIfNotProvided change ensures messages are only created
    # in conversations the actor has access to (via conversation policies which check
    # workspace membership), or creates a new conversation for the actor
    policy action_type(:create) do
      authorize_if actor_present()
    end

    # Destroy: users can delete messages in conversations within their workspace
    policy action_type(:destroy) do
      authorize_if expr(
                     conversation.workspace.owner_id == ^actor(:id) or
                       exists(conversation.workspace.memberships, user_id == ^actor(:id))
                   )
    end
  end

  pub_sub do
    module CitadelWeb.Endpoint
    prefix "chat"

    publish :create, ["messages", :conversation_id] do
      transform fn %{data: message} ->
        %{text: message.text, id: message.id, source: message.source}
      end
    end

    publish :create_response, ["messages", :conversation_id] do
      transform fn %{data: message} ->
        %{text: message.text, id: message.id, source: message.source}
      end
    end
  end

  attributes do
    timestamps()
    uuid_v7_primary_key :id, writable?: true

    attribute :text, :string do
      constraints allow_empty?: true, trim?: false
      public? true
      allow_nil? false
    end

    attribute :tool_calls, {:array, :map}
    attribute :tool_results, {:array, :map}

    attribute :source, Citadel.Chat.Message.Types.Source do
      allow_nil? false
      public? true
      default :user
    end

    attribute :complete, :boolean do
      allow_nil? false
      default true
    end
  end

  relationships do
    belongs_to :conversation, Citadel.Chat.Conversation do
      public? true
      allow_nil? false
    end

    belongs_to :response_to, __MODULE__ do
      public? true
    end

    has_one :response, __MODULE__ do
      public? true
      destination_attribute :response_to_id
    end
  end

  calculations do
    calculate :needs_response, :boolean do
      calculation expr(source == :user and not exists(response))
    end
  end

  identities do
    identity :unique_id, [:id]
  end
end
