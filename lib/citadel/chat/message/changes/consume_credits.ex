defmodule Citadel.Chat.Message.Changes.ConsumeCredits do
  @moduledoc """
  Handles credit reservation and adjustment for AI message responses.

  Uses a reserve/adjust pattern to prevent TOCTOU race conditions:
  1. Resolves the organization from message -> conversation -> workspace -> organization
  2. Reserves credits upfront before AI call (atomically)
  3. After AI call completes, adjusts reservation to actual cost

  This ensures that concurrent requests cannot overdraw credits, as the
  reservation happens atomically with a database lock.
  """

  require Ash.Query
  require Logger

  alias Citadel.Billing
  alias Citadel.Billing.Credits

  @doc """
  Reserves credits upfront before making an AI call.

  This atomically reserves the maximum expected credits, preventing TOCTOU
  race conditions. The reservation will be adjusted to actual cost after
  the AI call completes.

  Returns `{:ok, %{organization_id: id, reserved_amount: amount}}` if credits
  were reserved, or `{:error, :insufficient_credits}` if not enough credits
  are available. Returns `{:error, :no_organization}` if the workspace is
  not linked to an organization (legacy workspaces).

  ## Examples

      iex> ConsumeCredits.reserve(message, context)
      {:ok, %{organization_id: "org-uuid", reserved_amount: 100}}

      iex> ConsumeCredits.reserve(message, context)
      {:error, :insufficient_credits}

  """
  @spec reserve(Ash.Resource.record(), map()) ::
          {:ok, %{organization_id: String.t(), reserved_amount: non_neg_integer()}}
          | {:error, :insufficient_credits | :no_organization}
  def reserve(message, context) do
    case resolve_organization_id(message, context) do
      {:ok, organization_id} ->
        reserved_amount = Credits.max_reservation_credits()

        case Billing.reserve_credits(
               organization_id,
               reserved_amount,
               "AI message reservation",
               %{reference_type: "message", reference_id: message.id},
               authorize?: false
             ) do
          {:ok, _entry} ->
            Logger.debug(
              "Reserved #{reserved_amount} credits for message #{message.id} " <>
                "from organization #{organization_id}"
            )

            {:ok, %{organization_id: organization_id, reserved_amount: reserved_amount}}

          {:error, %Ash.Error.Invalid{} = error} ->
            if has_insufficient_credits_error?(error) do
              balance = Billing.get_organization_balance!(organization_id, authorize?: false)

              Logger.warning(
                "Insufficient credits to reserve for message #{message.id}. " <>
                  "Organization #{organization_id} has #{balance} credits, " <>
                  "needed #{reserved_amount}."
              )

              {:error, :insufficient_credits}
            else
              Logger.error(
                "Failed to reserve credits for message #{message.id}: #{inspect(error)}"
              )

              {:error, :insufficient_credits}
            end

          {:error, error} ->
            Logger.error(
              "Failed to reserve credits for message #{message.id}: #{inspect(error)}"
            )

            {:error, :insufficient_credits}
        end

      {:error, :no_organization} = error ->
        error
    end
  end

  @doc """
  Adjusts a previous reservation to the actual cost after AI call completion.

  If actual cost < reserved: credits are refunded
  If actual cost > reserved: logged as warning (overage absorbed by reservation)
  If actual cost == 0: full refund (operation failed/cancelled)

  ## Examples

      iex> token_usage = %LangChain.TokenUsage{input: 1000, output: 500}
      iex> ConsumeCredits.adjust(reservation, token_usage, message_id)
      :ok

  """
  @spec adjust(
          %{organization_id: String.t(), reserved_amount: non_neg_integer()},
          LangChain.TokenUsage.t() | nil,
          String.t(),
          keyword()
        ) :: :ok
  def adjust(reservation, token_usage, message_id, opts \\ []) do
    %{organization_id: organization_id, reserved_amount: reserved_amount} = reservation
    model = Keyword.get(opts, :model)
    actual_cost = Credits.calculate_cost(token_usage, model: model)

    input_tokens = if token_usage, do: token_usage.input || 0, else: 0
    output_tokens = if token_usage, do: token_usage.output || 0, else: 0

    description =
      "AI message adjustment (#{input_tokens} input tokens, #{output_tokens} output tokens, " <>
        "reserved: #{reserved_amount}, actual: #{actual_cost})"

    cond do
      actual_cost == reserved_amount ->
        Logger.debug(
          "No adjustment needed for message #{message_id}: " <>
            "actual cost #{actual_cost} equals reserved #{reserved_amount}"
        )

        :ok

      actual_cost > reserved_amount ->
        Logger.warning(
          "Actual cost #{actual_cost} exceeded reservation #{reserved_amount} " <>
            "for message #{message_id}. Overage absorbed."
        )

        :ok

      true ->
        case Billing.adjust_reservation(
               organization_id,
               reserved_amount,
               actual_cost,
               description,
               %{reference_type: "message", reference_id: message_id},
               authorize?: false
             ) do
          {:ok, _entry} ->
            refunded = reserved_amount - actual_cost

            Logger.debug(
              "Adjusted reservation for message #{message_id}: " <>
                "refunded #{refunded} credits (reserved: #{reserved_amount}, actual: #{actual_cost})"
            )

            :ok

          {:error, error} ->
            Logger.error(
              "Failed to adjust reservation for message #{message_id}: #{inspect(error)}"
            )

            :ok
        end
    end
  end

  @doc """
  Refunds a full reservation when an AI call fails or is cancelled.

  ## Examples

      iex> ConsumeCredits.refund(reservation, message_id)
      :ok

  """
  @spec refund(
          %{organization_id: String.t(), reserved_amount: non_neg_integer()},
          String.t()
        ) :: :ok
  def refund(reservation, message_id) do
    %{organization_id: organization_id, reserved_amount: reserved_amount} = reservation

    description = "AI message cancellation refund"

    case Billing.adjust_reservation(
           organization_id,
           reserved_amount,
           0,
           description,
           %{reference_type: "message", reference_id: message_id},
           authorize?: false
         ) do
      {:ok, _entry} ->
        Logger.debug(
          "Refunded full reservation of #{reserved_amount} credits for message #{message_id}"
        )

        :ok

      {:error, error} ->
        Logger.error("Failed to refund reservation for message #{message_id}: #{inspect(error)}")
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

  defp has_insufficient_credits_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn error ->
      case error do
        %Ash.Error.Changes.InvalidAttribute{field: :amount, message: msg} ->
          String.contains?(msg, "insufficient credits")

        _ ->
          false
      end
    end)
  end
end
