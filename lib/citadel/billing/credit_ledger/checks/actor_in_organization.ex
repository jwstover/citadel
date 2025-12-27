defmodule Citadel.Billing.CreditLedger.Checks.ActorInOrganization do
  @moduledoc """
  Policy check that authorizes if the actor is a member of the organization.
  Works with generic actions by extracting organization_id from the ActionInput.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_opts), do: "actor is a member of the organization"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, context, _opts) do
    org_id = get_organization_id(context)

    case org_id do
      nil -> false
      id -> actor_in_organization?(actor.id, id)
    end
  end

  defp get_organization_id(%{subject: %Ash.ActionInput{} = input}) do
    Ash.ActionInput.get_argument(input, :organization_id)
  end

  defp get_organization_id(%{subject: %Ash.Changeset{} = changeset}) do
    Ash.Changeset.get_argument(changeset, :organization_id) ||
      Ash.Changeset.get_attribute(changeset, :organization_id)
  end

  defp get_organization_id(_), do: nil

  defp actor_in_organization?(user_id, organization_id) do
    Citadel.Accounts.OrganizationMembership
    |> Ash.Query.filter(user_id == ^user_id and organization_id == ^organization_id)
    |> Ash.exists?(authorize?: false)
  end
end
