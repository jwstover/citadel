defmodule Citadel.Billing.Checks.HasSufficientCredits do
  @moduledoc """
  Policy check that verifies the organization has sufficient credits for AI operations.

  Used on Message.create action to enforce credit limits.
  Messages inherit workspace context through their conversation relationship.

  Path: Message -> Conversation -> Workspace -> Organization

  If no organization can be determined (e.g., workspaces without organizations),
  the check passes to maintain backwards compatibility.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias Citadel.Billing.Credits

  @impl true
  def describe(_opts) do
    "organization has sufficient credits"
  end

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(_actor, context, _opts) do
    case get_organization_id(context) do
      nil -> true
      org_id -> has_credits?(org_id)
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
    # Use the global action that allows multitenancy-free access
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

  defp has_credits?(organization_id) do
    case Credits.check_sufficient_credits(organization_id) do
      {:ok, _balance} -> true
      {:error, :insufficient_credits, _balance} -> false
    end
  end
end
