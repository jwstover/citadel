defmodule Citadel.Billing.Checks.HasSufficientCredits do
  @moduledoc """
  Policy check that verifies the organization exists for AI operations.

  Used on Message.create action to validate that the workspace has an
  organization before allowing message creation.

  Path: Message -> Conversation -> Workspace -> Organization

  ## Credit Validation Strategy

  This check does NOT validate the actual credit balance. Balance validation
  happens atomically during `ConsumeCredits.reserve()` which uses PostgreSQL
  advisory locks to prevent race conditions. Doing a non-atomic balance check
  here would create a TOCTOU vulnerability.

  Instead, this check simply ensures:
  1. An organization exists for the workspace
  2. The organization has a subscription

  The atomic reservation during the AI call will reject the request if
  insufficient credits are available.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_opts) do
    "organization exists and has subscription"
  end

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(_actor, context, _opts) do
    case get_organization_id(context) do
      nil -> false
      org_id -> has_subscription?(org_id)
    end
  end

  defp get_organization_id(%Ash.Changeset{} = changeset) do
    conversation_id =
      Ash.Changeset.get_argument(changeset, :conversation_id) ||
        Ash.Changeset.get_attribute(changeset, :conversation_id)

    if conversation_id do
      get_org_from_conversation(conversation_id)
    else
      case changeset.tenant do
        nil -> nil
        workspace_id -> get_org_from_workspace(workspace_id)
      end
    end
  end

  defp get_organization_id(%{changeset: %Ash.Changeset{} = changeset}) do
    get_organization_id(changeset)
  end

  defp get_organization_id(%{subject: %Ash.Changeset{} = changeset}) do
    get_organization_id(changeset)
  end

  defp get_organization_id(_), do: nil

  defp get_org_from_conversation(conversation_id) do
    case Citadel.Chat.get_conversation_global(conversation_id, authorize?: false) do
      {:ok, %{workspace_id: workspace_id}} when not is_nil(workspace_id) ->
        get_org_from_workspace(workspace_id)

      _ ->
        nil
    end
  end

  defp get_org_from_workspace(workspace_id) do
    case Citadel.Accounts.Workspace
         |> Ash.Query.filter(id == ^workspace_id)
         |> Ash.Query.select([:organization_id])
         |> Ash.read_one(authorize?: false) do
      {:ok, %{organization_id: org_id}} -> org_id
      _ -> nil
    end
  end

  defp has_subscription?(organization_id) do
    case Citadel.Billing.get_subscription_by_organization(organization_id, authorize?: false) do
      {:ok, subscription} -> subscription.status == :active
      _ -> false
    end
  end
end
