defmodule Citadel.Chat.Conversation do
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub],
    authorizers: [Ash.Policy.Authorizer]

  oban do
    triggers do
      trigger :name_conversation do
        actor_persister Citadel.AiAgentActorPersister
        action :generate_name
        queue :conversations
        lock_for_update? false
        worker_module_name Citadel.Chat.Message.Workers.NameConversation
        scheduler_module_name Citadel.Chat.Message.Schedulers.NameConversation
        where expr(needs_title)
      end
    end
  end

  postgres do
    table "conversations"
    repo Citadel.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title]
      change relate_actor(:user)
    end

    update :generate_name do
      accept []
      transaction? false
      require_atomic? false
      change Citadel.Chat.Conversation.Changes.GenerateName
    end

    read :my_conversations do
      filter expr(user_id == ^actor(:id))
    end
  end

  policies do
    # Allow AshAi actor (background jobs) full access for naming conversations
    bypass actor_attribute_equals(:__struct__, AshAi) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  pub_sub do
    module CitadelWeb.Endpoint
    prefix "chat"

    publish_all :create, ["conversations", :user_id] do
      transform & &1.data
    end

    publish_all :update, ["conversations", :user_id] do
      transform & &1.data
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :messages, Citadel.Chat.Message do
      public? true
    end

    belongs_to :user, Citadel.Accounts.User do
      public? true
      allow_nil? false
    end
  end

  calculations do
    calculate :needs_title, :boolean do
      calculation expr(
                    is_nil(title) and
                      (count(messages) > 3 or
                         (count(messages) > 1 and inserted_at < ago(10, :minute)))
                  )
    end
  end
end
