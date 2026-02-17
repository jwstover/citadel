defmodule Citadel.Integrations.GitHubConnection do
  @moduledoc """
  Resource for storing GitHub connection credentials per workspace.

  Stores encrypted GitHub Personal Access Tokens (PATs) that enable
  AI chat agents to access GitHub repositories via MCP tools.

  Only workspace owners can create/update/delete connections, but all
  workspace members can read (to use the tools in chat).
  """

  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Integrations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "github_connections"
    repo Citadel.Repo

    references do
      reference :workspace, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept []
      argument :pat, :string, allow_nil?: false, sensitive?: true

      change Citadel.Integrations.GitHubConnection.Changes.EncryptAndValidatePat
      change Citadel.Integrations.GitHubConnection.Changes.SetWorkspaceFromTenant
    end

    read :for_workspace do
      argument :workspace_id, :uuid, allow_nil?: false
      filter expr(workspace_id == ^arg(:workspace_id))
      get? true
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
      authorize_if Citadel.Integrations.GitHubConnection.Checks.TenantWorkspaceOwner
    end

    policy action_type(:destroy) do
      authorize_if expr(workspace.owner_id == ^actor(:id))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :pat_encrypted, Citadel.Encrypted.Binary do
      allow_nil? false
      sensitive? true
    end

    attribute :github_username, :string do
      allow_nil? true
      description "Cached GitHub username from validation"
    end

    attribute :workspace_id, :uuid do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace do
      define_attribute? false
    end
  end

  identities do
    identity :unique_workspace, [:workspace_id]
  end
end
