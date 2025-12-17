defmodule Citadel.Integrations.GitHubConnection.Checks.TenantWorkspaceOwner do
  @moduledoc """
  Policy check to verify if the actor is the owner of the tenant workspace.

  This check is used for write actions on resources where only workspace
  owners should be able to create/update/delete records.
  """
  use Ash.Policy.SimpleCheck

  def describe(_opts) do
    "actor is the owner of the tenant workspace"
  end

  def match?(actor, %{changeset: %{tenant: tenant}}, _opts)
      when not is_nil(actor) and not is_nil(tenant) do
    actor_id = Map.get(actor, :id)

    if is_nil(actor_id) do
      false
    else
      workspace_owner?(actor_id, tenant)
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp workspace_owner?(actor_id, workspace_id) do
    case Ash.get(Citadel.Accounts.Workspace, workspace_id, authorize?: false) do
      {:ok, workspace} -> workspace.owner_id == actor_id
      _ -> false
    end
  end
end
