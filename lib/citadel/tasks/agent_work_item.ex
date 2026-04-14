defmodule Citadel.Tasks.AgentWorkItem do
  @moduledoc false
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias Citadel.Tasks.AgentWorkItem.Types.{WorkItemStatus, WorkItemType}

  postgres do
    table "agent_work_items"
    repo Citadel.Repo

    references do
      reference :task, on_delete: :delete
      reference :comment, on_delete: :nilify
      reference :agent_run, on_delete: :nilify
    end

    custom_indexes do
      index [:task_id],
        unique: true,
        where: "status IN ('pending', 'claimed')",
        name: "agent_work_items_one_active_per_task"
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:type, :task_id, :comment_id, :session_id]

      change Citadel.Tasks.Changes.InheritTaskWorkspace
    end

    update :claim do
      accept [:agent_run_id]

      validate attribute_equals(:status, :pending)

      change set_attribute(:status, :claimed)
    end

    update :complete do
      accept []

      validate attribute_equals(:status, :claimed)

      change set_attribute(:status, :completed)
    end

    update :cancel do
      accept []

      validate attribute_in(:status, [:pending, :claimed])

      change set_attribute(:status, :cancelled)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     workspace.owner_id == ^actor(:id) or
                       exists(workspace.memberships, user_id == ^actor(:id))
                   )
    end

    policy action_type(:create) do
      authorize_if Citadel.Accounts.Checks.TenantWorkspaceMember
    end

    policy action_type(:update) do
      authorize_if expr(
                     workspace.owner_id == ^actor(:id) or
                       exists(workspace.memberships, user_id == ^actor(:id))
                   )
    end
  end

  pub_sub do
    module CitadelWeb.Endpoint
    prefix "tasks"

    publish :create, ["agent_work_items", :task_id]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :type, WorkItemType do
      allow_nil? false
      public? true
    end

    attribute :status, WorkItemStatus do
      default :pending
      allow_nil? false
      public? true
    end

    attribute :session_id, :string do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
    belongs_to :task, Citadel.Tasks.Task, public?: true, allow_nil?: false
    belongs_to :comment, Citadel.Tasks.TaskActivity, public?: true, allow_nil?: true
    belongs_to :agent_run, Citadel.Tasks.AgentRun, public?: true, allow_nil?: true
  end
end
