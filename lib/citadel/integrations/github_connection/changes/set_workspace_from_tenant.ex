defmodule Citadel.Integrations.GitHubConnection.Changes.SetWorkspaceFromTenant do
  @moduledoc """
  Sets the workspace_id attribute from the tenant context.

  This ensures workspace_id is set from the multitenancy tenant rather than
  requiring it to be explicitly passed as an attribute.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, context) do
    case context do
      %{tenant: tenant} when not is_nil(tenant) ->
        Ash.Changeset.force_change_attribute(changeset, :workspace_id, tenant)

      _ ->
        Ash.Changeset.add_error(changeset, field: :workspace_id, message: "tenant is required")
    end
  end
end
