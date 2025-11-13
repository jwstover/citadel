defmodule Citadel.Accounts.WorkspaceMembership do
  @moduledoc """
  Represents a user's membership in a workspace.
  This is a join table that connects users to workspaces.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspace_memberships"
    repo Citadel.Repo
  end

  code_interface do
    define :join, action: :join
    define :list, action: :read
    define :leave, action: :leave
  end

  actions do
    defaults [:read]

    create :join do
      accept []

      argument :user_id, :uuid do
        allow_nil? false
      end

      argument :workspace_id, :uuid do
        allow_nil? false
      end

      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.force_change_attribute(
          :user_id,
          Ash.Changeset.get_argument(changeset, :user_id)
        )
        |> Ash.Changeset.force_change_attribute(
          :workspace_id,
          Ash.Changeset.get_argument(changeset, :workspace_id)
        )
      end
    end

    destroy :leave do
      # Validate that the user leaving is not the workspace owner
      require_atomic? false
      validate {Citadel.Accounts.WorkspaceMembership.Changes.PreventOwnerLeaving, []}
    end
  end

  policies do
    # Workspace owner or members can create memberships (invite users)
    policy action_type(:create) do
      authorize_if {Citadel.Accounts.Checks.CanManageWorkspaceMembership, []}
    end

    # Users can read memberships in workspaces they belong to, or their own memberships
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if expr(workspace.owner_id == ^actor(:id))
      authorize_if expr(exists(workspace.memberships, user_id == ^actor(:id)))
    end

    # Workspace owner can destroy memberships (remove users)
    policy action_type(:destroy) do
      authorize_if expr(workspace.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Citadel.Accounts.User do
      primary_key? true
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :workspace, Citadel.Accounts.Workspace do
      primary_key? true
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_membership, [:user_id, :workspace_id]
  end
end
