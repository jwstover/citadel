defmodule Citadel.Accounts.WorkspaceInvitation do
  @moduledoc """
  Represents an invitation for a user to join a workspace.
  Invitations have a unique token and expiration date.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspace_invitations"
    repo Citadel.Repo
  end

  code_interface do
    define :create, action: :create, args: [:email, :workspace_id]
    define :list, action: :read
    define :get_by_token, action: :read, get_by: [:token]
    define :accept, action: :accept
    define :revoke, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:email, :workspace_id]

      # Auto-generate token and set expiration
      change {Citadel.Accounts.WorkspaceInvitation.Changes.GenerateToken, []}
      change {Citadel.Accounts.WorkspaceInvitation.Changes.SetExpiration, []}
      change relate_actor(:invited_by)

      # Enqueue email notification (runs after_action)
      change {Citadel.Accounts.WorkspaceInvitation.Changes.EnqueueInvitationEmail, []}
    end

    update :accept do
      accept []
      require_atomic? false

      # Validate invitation is still valid
      validate {Citadel.Accounts.WorkspaceInvitation.Changes.ValidateInvitation, []}

      # Create workspace membership and mark as accepted
      change {Citadel.Accounts.WorkspaceInvitation.Changes.AcceptInvitation, []}
    end

    # Internal update action for testing/admin purposes
    update :update do
      accept [:expires_at, :accepted_at]
    end
  end

  policies do
    # Workspace owner or members can create invitations
    policy action_type(:create) do
      authorize_if {Citadel.Accounts.Checks.CanCreateWorkspaceInvitation, []}
    end

    # Users can read invitations in workspaces they belong to, or by token
    policy action_type(:read) do
      authorize_if expr(workspace.owner_id == ^actor(:id))
      authorize_if expr(exists(workspace.memberships, user_id == ^actor(:id)))
      authorize_if {Citadel.Accounts.Checks.HasValidInvitationToken, []}
    end

    # Anyone with valid token can accept invitation
    policy action_type(:update) do
      authorize_if {Citadel.Accounts.Checks.HasValidInvitationToken, []}
    end

    # Workspace owner can revoke invitations
    policy action_type(:destroy) do
      authorize_if expr(workspace.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :token, :string do
      allow_nil? false
      public? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :accepted_at, :utc_datetime_usec do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :invited_by, Citadel.Accounts.User do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  calculations do
    calculate :is_expired, :boolean, expr(expires_at < now())
    calculate :is_accepted, :boolean, expr(not is_nil(accepted_at))
  end

  identities do
    identity :unique_token, [:token]
  end
end
