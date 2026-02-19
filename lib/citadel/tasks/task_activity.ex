defmodule Citadel.Tasks.TaskActivity do
  @moduledoc false
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Citadel.Tasks.TaskActivity.Types.{ActivityType, ActorType}

  postgres do
    table "task_activities"
    repo Citadel.Repo

    references do
      reference :task, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:body, :task_id, :metadata, :actor_type, :actor_display_name]

      change relate_actor(:user)
      change Citadel.Tasks.Changes.InheritTaskWorkspace
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

    policy action_type(:destroy) do
      authorize_if expr(
                     workspace.owner_id == ^actor(:id) or
                       exists(workspace.memberships, user_id == ^actor(:id))
                   )
    end
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

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
    belongs_to :task, Citadel.Tasks.Task, public?: true, allow_nil?: false
    belongs_to :user, Citadel.Accounts.User, allow_nil?: true
  end
end
