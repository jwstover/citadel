defmodule Citadel.Accounts.OrganizationMembership.Types.Role do
  @moduledoc """
  The role a user has within an organization.

  - :owner - Full control, can delete the organization
  - :admin - Can manage members and workspaces
  - :member - Basic access to organization workspaces
  """
  use Ash.Type.Enum, values: [:owner, :admin, :member]
end
