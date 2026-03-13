defmodule Citadel.Projects do
  @moduledoc """
  The Projects domain, managing projects that link workspaces to git repositories.
  """
  use Ash.Domain,
    otp_app: :citadel

  resources do
    resource Citadel.Projects.Project do
      define :create_project, action: :create
      define :get_project, action: :read, get_by: [:id]
      define :list_projects, action: :list
      define :update_project, action: :update, get_by: [:id]
      define :destroy_project, action: :destroy
    end
  end
end
