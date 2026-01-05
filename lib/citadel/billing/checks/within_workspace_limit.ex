defmodule Citadel.Billing.Checks.WithinWorkspaceLimit do
  @moduledoc """
  Policy check that verifies the organization is within its workspace limit.

  Used on Workspace.create action to enforce subscription tier limits.
  Workspaces without an organization_id are allowed (legacy/personal workspaces).
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias Citadel.Billing.Plan

  @impl true
  def describe(_opts) do
    "organization is within workspace limit"
  end

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(_actor, context, _opts) do
    organization_id = get_organization_id(context)

    case organization_id do
      nil -> true
      org_id -> within_limit?(org_id)
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

  defp get_organization_id(_), do: nil

  defp within_limit?(organization_id) do
    tier = get_organization_tier(organization_id)
    max_workspaces = Plan.max_workspaces(tier)
    current_count = count_organization_workspaces(organization_id)

    current_count < max_workspaces
  end

  defp get_organization_tier(organization_id) do
    case Citadel.Billing.get_subscription_by_organization(organization_id, authorize?: false) do
      {:ok, subscription} -> subscription.tier
      _ -> :free
    end
  end

  defp count_organization_workspaces(organization_id) do
    Citadel.Accounts.Workspace
    |> Ash.Query.filter(organization_id == ^organization_id)
    |> Ash.count!(authorize?: false)
  end
end
