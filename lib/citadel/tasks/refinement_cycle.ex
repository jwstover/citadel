defmodule Citadel.Tasks.RefinementCycle do
  @moduledoc false
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "refinement_cycles"
    repo Citadel.Repo

    references do
      reference :agent_run, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:agent_run_id, :max_iterations, :evaluator_config]

      change Citadel.Tasks.Changes.InheritAgentRunWorkspace
    end

    read :get_by_agent_run do
      argument :agent_run_id, :uuid, allow_nil?: false

      filter expr(agent_run_id == ^arg(:agent_run_id))
      prepare build(sort: [inserted_at: :desc], limit: 1)
    end

    update :update do
      require_atomic? false
      accept [:status, :current_iteration, :final_score]
    end

    update :complete do
      require_atomic? false
      accept []

      argument :final_score, :float, allow_nil?: false

      change set_attribute(:status, :passed)
      change set_attribute(:final_score, arg(:final_score))
    end

    update :fail do
      require_atomic? false
      accept []

      argument :reason, :atom do
        constraints one_of: [:failed_max_iterations, :error]
        default :failed_max_iterations
      end

      change set_attribute(:status, arg(:reason))
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

    publish :create, ["refinement", :agent_run_id]
    publish :update, ["refinement", :agent_run_id]
    publish :complete, ["refinement", :agent_run_id]
    publish :fail, ["refinement", :agent_run_id]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:running, :passed, :failed_max_iterations, :error]
      default :running
      allow_nil? false
      public? true
    end

    attribute :max_iterations, :integer, default: 3, allow_nil?: false, public?: true
    attribute :current_iteration, :integer, default: 0, allow_nil?: false, public?: true
    attribute :evaluator_config, :map, default: %{}, public?: true
    attribute :final_score, :float, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
    belongs_to :agent_run, Citadel.Tasks.AgentRun, public?: true, allow_nil?: false

    has_many :iterations, Citadel.Tasks.RefinementIteration
  end
end
