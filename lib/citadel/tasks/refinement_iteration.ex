defmodule Citadel.Tasks.RefinementIteration do
  @moduledoc false
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "refinement_iterations"
    repo Citadel.Repo

    references do
      reference :refinement_cycle, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :refinement_cycle_id,
        :iteration_number,
        :evaluation_result,
        :score,
        :feedback,
        :status,
        :started_at,
        :completed_at
      ]

      change Citadel.Tasks.Changes.InheritRefinementCycleWorkspace
    end

    read :list_by_cycle do
      argument :refinement_cycle_id, :uuid, allow_nil?: false

      filter expr(refinement_cycle_id == ^arg(:refinement_cycle_id))
      prepare build(sort: [iteration_number: :asc])
    end

    update :update do
      require_atomic? false
      accept [:status, :completed_at, :evaluation_result, :score, :feedback]
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

    publish_all :create, ["refinement", :refinement_cycle_id]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :iteration_number, :integer, allow_nil?: false, public?: true

    attribute :evaluation_result, :map, default: %{}, public?: true
    attribute :score, :float, public?: true
    attribute :feedback, :string, public?: true

    attribute :status, :atom do
      constraints one_of: [:evaluated, :refined, :accepted]
      default :evaluated
      allow_nil? false
      public? true
    end

    attribute :started_at, :utc_datetime_usec, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
    belongs_to :refinement_cycle, Citadel.Tasks.RefinementCycle, public?: true, allow_nil?: false
  end
end
