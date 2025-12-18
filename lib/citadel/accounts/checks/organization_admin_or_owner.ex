defmodule Citadel.Accounts.Checks.OrganizationAdminOrOwner do
  @moduledoc """
  Policy check that authorizes if the actor is an admin or owner of the organization.
  Works with create actions by extracting organization_id from the changeset.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_opts) do
    "actor is an admin or owner of the organization"
  end

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, context, _opts) do
    organization_id = get_organization_id(context)

    case organization_id do
      nil -> false
      org_id -> actor_is_admin_or_owner?(actor.id, org_id)
    end
  end

  defp get_organization_id(%Ash.Changeset{} = changeset) do
    Ash.Changeset.get_argument(changeset, :organization_id) ||
      Ash.Changeset.get_attribute(changeset, :organization_id)
  end

  defp get_organization_id(%{changeset: %Ash.Changeset{} = changeset}) do
    get_organization_id(changeset)
  end

  defp get_organization_id(%{subject: %Ash.Changeset{} = changeset}) do
    get_organization_id(changeset)
  end

  defp get_organization_id(%{data: %{organization_id: org_id}}) when not is_nil(org_id) do
    org_id
  end

  defp get_organization_id(_), do: nil

  defp actor_is_admin_or_owner?(user_id, organization_id) do
    Citadel.Accounts.OrganizationMembership
    |> Ash.Query.filter(
      user_id == ^user_id and
        organization_id == ^organization_id and
        role in [:owner, :admin]
    )
    |> Ash.exists?(authorize?: false)
  end
end
