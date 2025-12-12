defmodule Citadel.Accounts do
  @moduledoc """
  The Accounts domain, managing users and authentication tokens.
  """
  use Ash.Domain, otp_app: :citadel, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Citadel.Accounts.Token

    resource Citadel.Accounts.User do
      define :set_password, action: :set_password, args: [:password, :password_confirmation]

      define :change_password,
        action: :change_password,
        args: [:current_password, :password, :password_confirmation]

      define :get_user_by_id, action: :read, get_by: [:id]
    end

    resource Citadel.Accounts.Workspace do
      define :create_workspace, action: :create, args: [:name]
      define :destroy_workspace, action: :destroy
      define :get_workspace_by_id, action: :read, get_by: [:id]
      define :list_workspaces, action: :read
      define :update_workspace, action: :update
    end

    resource Citadel.Accounts.WorkspaceMembership do
      define :add_workspace_member, action: :join, args: [:user_id, :workspace_id]
      define :list_workspace_members, action: :read
      define :remove_workspace_member, action: :leave
    end

    resource Citadel.Accounts.WorkspaceInvitation do
      define :accept_invitation, action: :accept
      define :create_invitation, action: :create, args: [:email, :workspace_id]
      define :get_invitation_by_token, action: :read, get_by: [:token]
      define :list_workspace_invitations, action: :read
      define :revoke_invitation, action: :destroy
    end

    resource Citadel.Accounts.ApiKey do
      define :create_api_key, action: :create, args: [:name, :expires_at, :user_id, :workspace_id]
      define :list_api_keys, action: :read
      define :destroy_api_key, action: :destroy
    end
  end
end
