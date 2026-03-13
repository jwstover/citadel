defmodule Citadel.Projects.Project do
  @moduledoc """
  Represents a project that links a workspace to a git repository.
  Agents work on projects — each project maps to a specific repository.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "projects"
    repo Citadel.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :list do
      prepare build(sort: [inserted_at: :desc])
    end

    create :create do
      accept [:name, :repository_url, :default_branch, :description, :workspace_id]
    end

    update :update do
      accept [:name, :repository_url, :default_branch, :description]
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

    policy action_type([:update, :destroy]) do
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

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :repository_url, :string, public?: true, allow_nil?: false
    attribute :default_branch, :string, public?: true, default: "main"
    attribute :description, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
  end

  identities do
    identity :unique_repo_per_workspace, [:repository_url, :workspace_id]
  end
end
