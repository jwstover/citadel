defmodule Citadel.Tasks.AgentRun do
  @moduledoc false
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "agent_runs"
    repo Citadel.Repo

    references do
      reference :task, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:task_id, :status]

      change relate_actor(:user)
      change Citadel.Tasks.Changes.InheritTaskWorkspace
    end

    update :update do
      require_atomic? false

      accept [
        :status,
        :session_id,
        :commits,
        :test_output,
        :logs,
        :error_message,
        :started_at,
        :completed_at
      ]

      change fn changeset, _ ->
        incoming = Ash.Changeset.get_attribute(changeset, :status)
        current = changeset.data.status

        if current == :input_requested and incoming in [:completed, :failed] do
          Ash.Changeset.force_change_attribute(changeset, :status, :input_requested)
        else
          changeset
        end
      end

      change Citadel.Tasks.Changes.SyncWorkItemStatus
    end

    update :request_input do
      require_atomic? false
      accept []

      validate attribute_equals(:status, :running)

      change set_attribute(:status, :input_requested)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change Citadel.Tasks.Changes.SyncWorkItemStatus
    end

    update :cancel do
      require_atomic? false
      accept []

      validate attribute_in(:status, [:pending, :running])

      change set_attribute(:status, :cancelled)
      change set_attribute(:error_message, "Manually cancelled by user")
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change Citadel.Tasks.Changes.SyncWorkItemStatus
    end

    create :claim_next do
      accept []

      change relate_actor(:user)
      change Citadel.Tasks.Changes.ClaimNextTask
    end

    read :list_by_task do
      argument :task_id, :uuid, allow_nil?: false

      filter expr(task_id == ^arg(:task_id))
      prepare build(sort: [inserted_at: :asc])
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

    publish :create, ["agent_runs", :task_id]
    publish :claim_next, ["agent_runs", :task_id]
    publish :update, ["agent_runs", :task_id]
    publish :cancel, ["agent_runs", :task_id]
    publish :request_input, ["agent_runs", :task_id]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:pending, :running, :completed, :failed, :cancelled, :input_requested]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :session_id, :string, public?: true
    attribute :commits, {:array, :map}, public?: true, default: []
    attribute :test_output, :string, public?: true
    attribute :logs, :string, public?: true
    attribute :error_message, :string, public?: true
    attribute :started_at, :utc_datetime_usec, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
    belongs_to :task, Citadel.Tasks.Task, public?: true, allow_nil?: false
    belongs_to :user, Citadel.Accounts.User, allow_nil?: true

    has_one :work_item, Citadel.Tasks.AgentWorkItem
    has_many :events, Citadel.Tasks.AgentRunEvent
  end
end
