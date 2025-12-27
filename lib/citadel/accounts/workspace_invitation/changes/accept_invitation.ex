defmodule Citadel.Accounts.WorkspaceInvitation.Changes.AcceptInvitation do
  @moduledoc """
  Accepts an invitation by creating a workspace membership and marking the invitation as accepted.

  When accepting an invitation, if the user is not already a member of the workspace's
  organization, they are automatically added as a member with the `:member` role.
  """
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    changeset = Ash.Changeset.force_change_attribute(changeset, :accepted_at, DateTime.utc_now())

    Ash.Changeset.after_action(changeset, fn _changeset, invitation ->
      handle_invitation_acceptance(invitation, context)
    end)
  end

  defp handle_invitation_acceptance(invitation, context) do
    case find_user_by_email(invitation.email) do
      {:ok, user} ->
        create_membership_for_user(invitation, user, context)

      {:error, _} ->
        {:error, "User with email #{invitation.email} not found"}
    end
  end

  defp create_membership_for_user(invitation, user, context) do
    with {:ok, org_id} <- get_workspace_organization_id(invitation.workspace_id),
         :ok <- ensure_org_membership(user.id, org_id, context),
         {:ok, _membership} <- create_workspace_membership(invitation, user, context) do
      {:ok, invitation}
    end
  end

  defp find_user_by_email(email) do
    Citadel.Accounts.User
    |> Ash.Query.filter(email == ^email)
    |> Ash.read_one(authorize?: false)
  end

  defp get_workspace_organization_id(workspace_id) do
    case Citadel.Accounts.Workspace
         |> Ash.Query.filter(id == ^workspace_id)
         |> Ash.Query.select([:organization_id])
         |> Ash.read_one(authorize?: false) do
      {:ok, %{organization_id: org_id}} when not is_nil(org_id) ->
        {:ok, org_id}

      _ ->
        {:error, "Workspace does not have an organization"}
    end
  end

  defp ensure_org_membership(user_id, organization_id, context) do
    if user_is_org_member?(user_id, organization_id) do
      :ok
    else
      create_org_membership(user_id, organization_id, context)
    end
  end

  defp user_is_org_member?(user_id, organization_id) do
    Citadel.Accounts.OrganizationMembership
    |> Ash.Query.filter(user_id == ^user_id and organization_id == ^organization_id)
    |> Ash.exists?(authorize?: false)
  end

  defp create_org_membership(user_id, organization_id, context) do
    case Citadel.Accounts.add_organization_member(
           organization_id,
           user_id,
           :member,
           Ash.Context.to_opts(context, authorize?: false)
         ) do
      {:ok, _membership} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp create_workspace_membership(invitation, user, context) do
    Citadel.Accounts.add_workspace_member(
      user.id,
      invitation.workspace_id,
      Ash.Context.to_opts(context, authorize?: false)
    )
  end
end
