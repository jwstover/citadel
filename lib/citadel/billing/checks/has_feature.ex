defmodule Citadel.Billing.Checks.HasFeature do
  @moduledoc """
  Policy check that verifies an organization has access to a specific feature.

  This is a generic check that works with any feature defined in the
  Citadel.Billing.Features catalog.

  ## Usage

      policy action(:export_data) do
        authorize_if HasFeature, feature: :data_export
      end

      policy action(:use_advanced_models) do
        authorize_if HasFeature, feature: :advanced_ai_models
      end

  ## Options

  - `:feature` (required) - The feature atom to check

  ## Context Requirements

  Requires organization_id in one of:
  - Changeset argument `:organization_id`
  - Changeset attribute `:organization_id`
  - Context data `%{organization_id: ...}`
  - Via workspace (changeset.tenant)
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias Citadel.Billing.{Features, Plan}

  @impl true
  def describe(opts) do
    feature = Keyword.fetch!(opts, :feature)
    feature_name = Features.name(feature)
    "organization has access to #{feature_name}"
  end

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(_actor, context, opts) do
    feature = Keyword.fetch!(opts, :feature)

    unless Features.valid_feature?(feature) do
      raise ArgumentError, "Invalid feature: #{inspect(feature)}"
    end

    organization_id = get_organization_id(context)

    case organization_id do
      nil -> false
      org_id -> has_feature?(org_id, feature)
    end
  end

  defp get_organization_id(%Ash.Changeset{} = changeset) do
    Ash.Changeset.get_argument(changeset, :organization_id) ||
      Ash.Changeset.get_attribute(changeset, :organization_id) ||
      get_org_from_workspace(changeset.tenant)
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

  defp get_org_from_workspace(nil), do: nil

  defp get_org_from_workspace(workspace_id) do
    case Citadel.Accounts.Workspace
         |> Ash.Query.filter(id == ^workspace_id)
         |> Ash.Query.select([:organization_id])
         |> Ash.read_one(authorize?: false) do
      {:ok, %{organization_id: org_id}} -> org_id
      _ -> nil
    end
  end

  defp has_feature?(organization_id, feature) do
    tier = get_organization_tier(organization_id)
    Plan.tier_has_feature?(tier, feature)
  end

  defp get_organization_tier(organization_id) do
    case Citadel.Billing.get_subscription_by_organization(organization_id, authorize?: false) do
      {:ok, subscription} -> subscription.tier
      _ -> :free
    end
  end
end
