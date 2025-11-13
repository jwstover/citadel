defmodule Citadel.Accounts.Workspace do
  @moduledoc """
  A workspace groups users together to collaborate on tasks and conversations.
  Each workspace has an owner who can manage the workspace and invite other users.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspaces"
    repo Citadel.Repo
  end

  code_interface do
    define :create, args: [:name]
    define :list, action: :read
    define :get_by_id, action: :read, get_by: [:id]
    define :update
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name]

      change relate_actor(:owner)
    end

    update :update do
      accept [:name]
    end
  end

  policies do
    # Any authenticated user can create a workspace
    policy action_type(:create) do
      authorize_if actor_present()
    end

    # For Phase 1.1: Only owner can read (will be expanded to members in Phase 1.2)
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
    end

    # Only the owner can update the workspace
    policy action_type(:update) do
      authorize_if relates_to_actor_via(:owner)
    end

    # Only the owner can destroy the workspace
    policy action_type(:destroy) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true

      constraints min_length: 1,
                  max_length: 100,
                  trim?: true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :owner, Citadel.Accounts.User do
      allow_nil? false
      attribute_writable? true
    end

    # Note: memberships and members relationships will be added in Phase 1.2
    # has_many :memberships, Citadel.Accounts.WorkspaceMembership
    #
    # many_to_many :members, Citadel.Accounts.User do
    #   through Citadel.Accounts.WorkspaceMembership
    #   source_attribute_on_join_resource :workspace_id
    #   destination_attribute_on_join_resource :user_id
    # end
  end
end
