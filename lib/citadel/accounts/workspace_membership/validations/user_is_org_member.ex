defmodule Citadel.Accounts.WorkspaceMembership.Validations.UserIsOrgMember do
  @moduledoc """
  Validates that a user is a member of the workspace's organization
  before they can be added to the workspace.

  This validation is skipped if the workspace has no organization (for backwards compatibility
  during migration).
  """
  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    user_id = Ash.Changeset.get_attribute(changeset, :user_id)
    workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)

    if is_nil(user_id) or is_nil(workspace_id) do
      :ok
    else
      validate_org_membership(user_id, workspace_id)
    end
  end

  defp validate_org_membership(user_id, workspace_id) do
    case get_workspace_organization_id(workspace_id) do
      nil ->
        # Workspace has no organization yet (backwards compatibility)
        :ok

      organization_id ->
        if user_is_org_member?(user_id, organization_id) do
          :ok
        else
          {:error,
           field: :user_id, message: "user must be a member of the workspace's organization"}
        end
    end
  end

  defp get_workspace_organization_id(workspace_id) do
    case Citadel.Accounts.Workspace
         |> Ash.Query.filter(id == ^workspace_id)
         |> Ash.Query.select([:organization_id])
         |> Ash.read_one(authorize?: false) do
      {:ok, %{organization_id: org_id}} -> org_id
      _ -> nil
    end
  end

  defp user_is_org_member?(user_id, organization_id) do
    Citadel.Accounts.OrganizationMembership
    |> Ash.Query.filter(user_id == ^user_id and organization_id == ^organization_id)
    |> Ash.exists?(authorize?: false)
  end
end
