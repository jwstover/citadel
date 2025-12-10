defmodule Citadel.Tasks.TaskAssignment do
  @moduledoc """
  Join resource linking tasks to assigned users.
  Enables multiple assignees per task through a many-to-many relationship.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "task_assignments"
    repo Citadel.Repo

    references do
      reference :task, index?: true, on_delete: :delete
      reference :assignee, index?: true, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     task.workspace.owner_id == ^actor(:id) or
                       exists(task.workspace.memberships, user_id == ^actor(:id))
                   )
    end

    policy action_type(:create) do
      authorize_if Citadel.Tasks.Checks.TaskWorkspaceMember
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(
                     task.workspace.owner_id == ^actor(:id) or
                       exists(task.workspace.memberships, user_id == ^actor(:id))
                   )
    end
  end

  attributes do
    uuid_v7_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :task, Citadel.Tasks.Task, allow_nil?: false
    belongs_to :assignee, Citadel.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_assignment, [:task_id, :assignee_id]
  end
end
