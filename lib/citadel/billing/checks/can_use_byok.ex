defmodule Citadel.Billing.Checks.CanUseBYOK do
  @moduledoc """
  Policy check that verifies the organization can use BYOK (Bring Your Own Key).

  Only Pro tier subscriptions can use BYOK. This check is used when setting
  or using a custom API key for AI operations.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias Citadel.Billing.Plan

  @impl true
  def describe(_opts) do
    "organization can use BYOK (Pro tier only)"
  end

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(_actor, context, _opts) do
    organization_id = get_organization_id(context)

    case organization_id do
      nil -> false
      org_id -> can_use_byok?(org_id)
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

  defp can_use_byok?(organization_id) do
    tier = get_organization_tier(organization_id)
    Plan.allows_byok?(tier)
  end

  defp get_organization_tier(organization_id) do
    case Citadel.Billing.get_subscription_by_organization(organization_id, authorize?: false) do
      {:ok, subscription} -> subscription.tier
      _ -> :free
    end
  end
end
