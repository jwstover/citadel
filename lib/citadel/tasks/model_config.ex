defmodule Citadel.Tasks.ModelConfig do
  @moduledoc """
  Stores named AI model configurations at the workspace level.
  Tasks and workflow steps reference these configs to tell agents which model to use.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "model_configs"
    repo Citadel.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :provider, :model, :temperature, :max_tokens, :is_default, :workspace_id]
    end

    update :update do
      accept [:name, :provider, :model, :temperature, :max_tokens]
    end

    update :unset_default do
      accept []
      change set_attribute(:is_default, false)
    end

    read :list do
      prepare build(sort: [inserted_at: :desc])
    end

    read :get_workspace_default do
      get? true
      filter expr(is_default == true)
    end

    update :set_default do
      accept []
      require_atomic? false
      change Citadel.Tasks.Changes.SetModelConfigDefault
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

    attribute :provider, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: [:anthropic, :openai]]

    attribute :model, :string, public?: true, allow_nil?: false
    attribute :temperature, :float, public?: true, default: 0.7
    attribute :max_tokens, :integer, public?: true
    attribute :is_default, :boolean, public?: true, default: false

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
  end

  identities do
    identity :unique_name_per_workspace, [:workspace_id, :name]
  end
end
