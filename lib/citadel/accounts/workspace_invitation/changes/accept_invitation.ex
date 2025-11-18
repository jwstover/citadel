defmodule Citadel.Accounts.WorkspaceInvitation.Changes.AcceptInvitation do
  @moduledoc """
  Accepts an invitation by creating a workspace membership and marking the invitation as accepted.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    # Set accepted_at timestamp
    changeset = Ash.Changeset.force_change_attribute(changeset, :accepted_at, DateTime.utc_now())

    # Create membership after the invitation is updated
    Ash.Changeset.after_action(changeset, fn _changeset, invitation ->
      handle_invitation_acceptance(invitation, context)
    end)
  end

  defp handle_invitation_acceptance(invitation, context) do
    # Get the user from the invitation email
    case find_user_by_email(invitation.email) do
      {:ok, user} ->
        create_membership_for_user(invitation, user, context)

      {:error, _} ->
        {:error, "User with email #{invitation.email} not found"}
    end
  end

  defp create_membership_for_user(invitation, user, context) do
    case create_membership(invitation, user, context) do
      {:ok, _membership} -> {:ok, invitation}
      {:error, error} -> {:error, error}
    end
  end

  defp find_user_by_email(email) do
    Citadel.Accounts.User
    |> Ash.Query.filter(email == ^email)
    |> Ash.read_one(authorize?: false)
  end

  defp create_membership(invitation, user, context) do
    Citadel.Accounts.add_workspace_member(
      user.id,
      invitation.workspace_id,
      Ash.Context.to_opts(context, authorize?: false)
    )
  end
end
