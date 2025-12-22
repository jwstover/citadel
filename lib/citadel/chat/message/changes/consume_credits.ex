defmodule Citadel.Chat.Message.Changes.ConsumeCredits do
  @moduledoc """
  Handles credit pre-check and post-charge for AI message responses.

  This module:
  1. Resolves the organization from message -> conversation -> workspace -> organization
  2. Checks sufficient credits before AI call
  3. Tracks token usage from successful responses
  4. Deducts credits after successful AI response
  """

  require Ash.Query
  require Logger

  alias Citadel.Billing
  alias Citadel.Billing.Credits

  @doc """
  Checks if the organization has sufficient credits before making an AI call.

  Returns `{:ok, organization_id}` if credits are available, or
  `{:error, :insufficient_credits}` if not. Returns `{:error, :no_organization}`
  if the workspace is not linked to an organization (legacy workspaces).

  ## Examples

      iex> ConsumeCredits.pre_check(message, context)
      {:ok, "org-uuid"}

      iex> ConsumeCredits.pre_check(message, context)
      {:error, :insufficient_credits}

  """
  @spec pre_check(Ash.Resource.record(), map()) ::
          {:ok, String.t()} | {:error, :insufficient_credits | :no_organization}
  def pre_check(message, context) do
    case resolve_organization_id(message, context) do
      {:ok, organization_id} ->
        case Credits.check_sufficient_credits(organization_id) do
          {:ok, _balance} ->
            {:ok, organization_id}

          {:error, :insufficient_credits, balance} ->
            Logger.warning(
              "Insufficient credits for message #{message.id}. " <>
                "Organization #{organization_id} has #{balance} credits."
            )

            {:error, :insufficient_credits}
        end

      {:error, :no_organization} = error ->
        error
    end
  end

  @doc """
  Deducts credits after a successful AI response based on actual token usage.

  Creates a credit ledger entry with the message ID as the reference.

  ## Examples

      iex> token_usage = %LangChain.TokenUsage{input: 1000, output: 500}
      iex> ConsumeCredits.post_charge(org_id, token_usage, message_id)
      :ok

  """
  @spec post_charge(String.t(), LangChain.TokenUsage.t() | nil, String.t(), keyword()) :: :ok
  def post_charge(organization_id, token_usage, message_id, opts \\ []) do
    model = Keyword.get(opts, :model)
    credits = Credits.calculate_cost(token_usage, model: model)

    input_tokens = if token_usage, do: token_usage.input || 0, else: 0
    output_tokens = if token_usage, do: token_usage.output || 0, else: 0

    description =
      "AI message response (#{input_tokens} input tokens, #{output_tokens} output tokens)"

    case Billing.deduct_credits(
           organization_id,
           credits,
           description,
           %{reference_type: "message", reference_id: message_id},
           authorize?: false
         ) do
      {:ok, _entry} ->
        Logger.debug(
          "Deducted #{credits} credits from organization #{organization_id} for message #{message_id}"
        )

        :ok

      {:error, error} ->
        Logger.error("Failed to deduct credits for message #{message_id}: #{inspect(error)}")

        :ok
    end
  end

  @doc """
  Resolves the organization_id from a message through the relationship chain:
  Message -> Conversation -> Workspace -> Organization

  Returns `{:ok, organization_id}` or `{:error, :no_organization}` if the
  workspace is not linked to an organization.
  """
  @spec resolve_organization_id(Ash.Resource.record(), map()) ::
          {:ok, String.t()} | {:error, :no_organization}
  def resolve_organization_id(message, _context) do
    # Use global read action to bypass multitenancy
    case Citadel.Chat.get_conversation_global(message.conversation_id,
           load: [workspace: [:organization_id]],
           authorize?: false
         ) do
      {:ok, %{workspace: %{organization_id: org_id}}} when not is_nil(org_id) ->
        {:ok, org_id}

      _ ->
        {:error, :no_organization}
    end
  end
end
