defmodule Citadel.Accounts.Checks.TenantWorkspaceMember do
  @moduledoc """
  Policy check to verify if the actor is a member of the tenant workspace.

  This check is used for create actions on multitenant resources where the tenant
  is set to a workspace_id. It ensures the actor has membership in that workspace
  (either as the owner or as an explicit member).
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts) do
    "actor is a member of the tenant workspace"
  end

  @impl true
  def match?(actor, %{changeset: %{tenant: tenant}}, _opts)
      when not is_nil(actor) and not is_nil(tenant) do
    actor_id = Map.get(actor, :id)

    if is_nil(actor_id) do
      false
    else
      owner_or_member?(actor_id, tenant)
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp owner_or_member?(actor_id, workspace_id) do
    require Ash.Query

    # Check if actor is the owner of the workspace
    is_owner =
      case Ash.get(Citadel.Accounts.Workspace, workspace_id, authorize?: false) do
        {:ok, workspace} -> workspace.owner_id == actor_id
        _ -> false
      end

    # If not owner, check if actor has a membership
    if is_owner do
      true
    else
      Citadel.Accounts.WorkspaceMembership
      |> Ash.Query.filter(workspace_id == ^workspace_id and user_id == ^actor_id)
      |> Ash.exists?(authorize?: false)
    end
  end
end
