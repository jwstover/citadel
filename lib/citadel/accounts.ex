defmodule Citadel.Accounts do
  @moduledoc """
  The Accounts domain, managing users and authentication tokens.
  """
  use Ash.Domain, otp_app: :citadel, extensions: [AshAi, AshAdmin.Domain]

  tools do
    tool :get_current_workspace, Citadel.Accounts.Workspace, :current do
      description "Returns the workspace ID associated with the current API key session"
    end
  end

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

    resource Citadel.Accounts.Organization do
      define :create_organization, action: :create, args: [:name]
      define :destroy_organization, action: :destroy
      define :get_organization_by_id, action: :read, get_by: [:id]
      define :get_organization_by_slug, action: :read, get_by: [:slug]
      define :list_organizations, action: :read
      define :update_organization, action: :update
    end

    resource Citadel.Accounts.OrganizationMembership do
      define :add_organization_member, action: :join, args: [:organization_id, :user_id, :role]
      define :list_organization_members, action: :read
      define :update_organization_member_role, action: :update_role
      define :remove_organization_member, action: :leave
    end

    resource Citadel.Accounts.Workspace do
      define :create_workspace, action: :create, args: [:name]
      define :current_workspace, action: :current
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
