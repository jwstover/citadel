defmodule Citadel.Integrations do
  @moduledoc """
  The Integrations domain for managing external service connections.

  This domain handles connections to external services like GitHub,
  allowing workspaces to configure integrations that enhance
  AI chat capabilities with external tools.
  """
  use Ash.Domain, otp_app: :citadel, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Citadel.Integrations.GitHubConnection do
      define :create_github_connection, action: :create, args: [:pat]
      define :get_github_connection, action: :read, get_by: [:id]
      define :get_workspace_github_connection, action: :for_workspace, args: [:workspace_id]
      define :delete_github_connection, action: :destroy
    end
  end
end
