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
    resource Citadel.Accounts.User

    resource Citadel.Accounts.Workspace do
      define :create_workspace, action: :create, args: [:name]
      define :list_workspaces, action: :read
      define :get_workspace_by_id, action: :read, get_by: [:id]
      define :update_workspace, action: :update
      define :destroy_workspace, action: :destroy
    end

    resource Citadel.Accounts.WorkspaceMembership do
      define :add_workspace_member, action: :join, args: [:user_id, :workspace_id]
      define :remove_workspace_member, action: :leave
      define :list_workspace_members, action: :read
    end

    resource Citadel.Accounts.WorkspaceInvitation do
      define :create_invitation, action: :create, args: [:email, :workspace_id]
      define :list_workspace_invitations, action: :read
      define :get_invitation_by_token, action: :read, get_by: [:token]
      define :accept_invitation, action: :accept
      define :revoke_invitation, action: :destroy
    end
  end
end
