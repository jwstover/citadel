defmodule Citadel.Tasks.TaskSummary do
  @moduledoc """
  A lightweight, read-only view of tasks exposing only the fields needed for compact listings.
  Backed by the existing `tasks` table with no migration required.
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
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
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

    attribute :human_id, :string do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :title, :string, public?: true, allow_nil?: false

    attribute :description, :string do
      public? true
      select_by_default? false
    end

    attribute :due_date, :date, public?: true

    attribute :priority, Citadel.Tasks.Task.Types.Priority do
      public? true
      default :medium
    end

    attribute :workspace_id, :uuid, allow_nil?: false
    attribute :task_state_id, :uuid, allow_nil?: false
    attribute :parent_task_id, :uuid
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace do
      define_attribute? false
      allow_nil? false
    end

    belongs_to :task_state, Citadel.Tasks.TaskState do
      define_attribute? false
      public? true
      allow_nil? false
    end

    belongs_to :parent_task, Citadel.Tasks.Task do
      define_attribute? false
      allow_nil? true
    end
  end
end
