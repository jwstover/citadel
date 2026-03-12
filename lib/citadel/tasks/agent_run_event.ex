defmodule Citadel.Tasks.AgentRunEvent do
  @moduledoc false
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "agent_run_events"
    repo Citadel.Repo

    references do
      reference :agent_run, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:event_type, :message, :metadata, :agent_run_id]

      change Citadel.Tasks.Changes.InheritAgentRunWorkspace
    end

    read :list_by_run do
      argument :agent_run_id, :uuid, allow_nil?: false

      filter expr(agent_run_id == ^arg(:agent_run_id))
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
  end

  pub_sub do
    module CitadelWeb.Endpoint
    prefix "tasks"

    publish :create, ["agent_run_events", :agent_run_id]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :event_type, :atom do
      constraints one_of: [:run_started, :run_completed, :run_failed, :error]
      allow_nil? false
      public? true
    end

    attribute :message, :string, public?: true
    attribute :metadata, :map, default: %{}, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
    belongs_to :agent_run, Citadel.Tasks.AgentRun, public?: true, allow_nil?: false
  end
end
