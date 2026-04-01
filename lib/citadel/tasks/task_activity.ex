defmodule Citadel.Tasks.TaskActivity do
  @moduledoc false
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias Citadel.Tasks.TaskActivity.Types.{ActivityType, ActorType}

  postgres do
    table "task_activities"
    repo Citadel.Repo

    references do
      reference :task, on_delete: :delete
      reference :parent_activity, on_delete: :nilify
      reference :agent_run, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:body, :task_id, :metadata, :actor_type, :actor_display_name]

      change relate_actor(:user)
      change Citadel.Tasks.Changes.InheritTaskWorkspace
    end

    create :create_comment do
      accept [:body, :task_id]

      change set_attribute(:type, :comment)
      change set_attribute(:actor_type, :user)
      change relate_actor(:user)
      change Citadel.Tasks.Changes.InheritTaskWorkspace
    end

    create :create_request_changes_comment do
      accept [:body, :task_id]

      change set_attribute(:type, :change_request)
      change set_attribute(:actor_type, :user)
      change relate_actor(:user)
      change Citadel.Tasks.Changes.InheritTaskWorkspace
      change Citadel.Tasks.Changes.RequestChanges
    end

    create :create_agent_run_activity do
      accept [:task_id, :agent_run_id]

      change set_attribute(:type, :agent_run)
      change set_attribute(:actor_type, :ai)
      change set_attribute(:actor_display_name, "Agent")
      change Citadel.Tasks.Changes.InheritTaskWorkspace
    end

    create :create_agent_question do
      accept [:body, :task_id, :agent_run_id]
      validate present(:agent_run_id)
      change set_attribute(:type, :question)
      change set_attribute(:actor_type, :ai)
      change relate_actor(:user)
      change Citadel.Tasks.Changes.InheritTaskWorkspace
      change Citadel.Tasks.Changes.RequestInput
    end

    create :create_question_response do
      accept [:body, :task_id, :parent_activity_id]

      change set_attribute(:type, :question_response)
      change set_attribute(:actor_type, :user)
      change relate_actor(:user)
      change Citadel.Tasks.Changes.InheritTaskWorkspace
      change Citadel.Tasks.Changes.CreateQuestionAnswer
    end

    read :list_by_task do
      argument :task_id, :uuid, allow_nil?: false

      filter expr(task_id == ^arg(:task_id))
      prepare build(sort: [inserted_at: :asc])
    end

    destroy :destroy_comment
  end

  policies do
    bypass action(:create_agent_run_activity) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(
                     workspace.owner_id == ^actor(:id) or
                       exists(workspace.memberships, user_id == ^actor(:id))
                   )
    end

    policy action_type(:create) do
      authorize_if Citadel.Accounts.Checks.TenantWorkspaceMember
    end

    policy action_type(:destroy) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  pub_sub do
    module CitadelWeb.Endpoint
    prefix "tasks"

    publish :create_comment, ["task_activities", :task_id]
    publish :create_request_changes_comment, ["task_activities", :task_id]
    publish :create_agent_run_activity, ["task_activities", :task_id]
    publish :create_agent_question, ["task_activities", :task_id]
    publish :create_question_response, ["task_activities", :task_id]
    publish :destroy_comment, ["task_activities", :task_id]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :type, ActivityType do
      allow_nil? false
      default :comment
    end

    attribute :body, :string, public?: true

    attribute :metadata, :map do
      default %{}
    end

    attribute :actor_type, ActorType do
      allow_nil? false
      default :user
    end

    attribute :actor_display_name, :string
    attribute :agent_run_id, :uuid, public?: true
    attribute :parent_activity_id, :uuid, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
    belongs_to :task, Citadel.Tasks.Task, public?: true, allow_nil?: false
    belongs_to :user, Citadel.Accounts.User, allow_nil?: true

    belongs_to :agent_run, Citadel.Tasks.AgentRun,
      public?: true,
      allow_nil?: true,
      attribute_writable?: true,
      define_attribute?: false

    belongs_to :parent_activity, Citadel.Tasks.TaskActivity,
      allow_nil?: true,
      attribute_writable?: true,
      define_attribute?: false
  end
end
