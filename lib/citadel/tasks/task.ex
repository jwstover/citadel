defmodule Citadel.Tasks.Task do
  @moduledoc """
  Represents a task item with a title, description, and associated state.
  Tasks are owned by users and can only be accessed by their owners.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tasks"
    repo Citadel.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :description, :task_state_id]
      change relate_actor(:user)
      change Citadel.Tasks.Changes.SetDefaultTaskState
    end

    update :update do
      primary? true
      accept [:title, :description, :task_state_id]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false
    attribute :description, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :task_state, Citadel.Tasks.TaskState, public?: true, allow_nil?: false
    belongs_to :user, Citadel.Accounts.User, allow_nil?: false
  end
end
