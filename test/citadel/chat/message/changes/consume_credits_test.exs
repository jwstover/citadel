defmodule Citadel.Chat.Message.Changes.ConsumeCreditsTest do
  use Citadel.DataCase, async: true

  alias Citadel.Billing
  alias Citadel.Billing.Credits
  alias Citadel.Chat.Message.Changes.ConsumeCredits

  setup do
    owner = generate(user())
    organization = generate(organization([], actor: owner))

    workspace =
      generate(workspace([organization_id: organization.id], actor: owner))

    conversation =
      generate(
        conversation(
          [workspace_id: workspace.id],
          actor: owner,
          tenant: workspace.id
        )
      )

    {:ok,
     owner: owner, organization: organization, workspace: workspace, conversation: conversation}
  end

  describe "resolve_organization_id/2" do
    test "resolves organization from message chain", %{
      owner: owner,
      organization: organization,
      workspace: workspace,
      conversation: conversation
    } do
      message =
        generate(
          message(
            [conversation_id: conversation.id],
            actor: owner,
            tenant: workspace.id,
            authorize?: false
          )
        )

      assert {:ok, org_id} = ConsumeCredits.resolve_organization_id(message, %{})
      assert org_id == organization.id
    end
  end

  describe "reserve/2" do
    test "returns reservation when credits are sufficient", %{
      owner: owner,
      organization: organization,
      workspace: workspace,
      conversation: conversation
    } do
      max_reservation = Credits.max_reservation_credits()
      Billing.add_credits!(organization.id, max_reservation, "Initial credits", authorize?: false)

      message =
        generate(
          message(
            [conversation_id: conversation.id],
            actor: owner,
            tenant: workspace.id,
            authorize?: false
          )
        )

      assert {:ok, reservation} = ConsumeCredits.reserve(message, %{})
      assert reservation.organization_id == organization.id
      assert reservation.reserved_amount == max_reservation

      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == 0
    end

    test "returns error when credits are insufficient", %{
      owner: owner,
      organization: _organization,
      workspace: workspace,
      conversation: conversation
    } do
      message =
        generate(
          message(
            [conversation_id: conversation.id],
            actor: owner,
            tenant: workspace.id,
            authorize?: false
          )
        )

      assert {:error, :insufficient_credits} = ConsumeCredits.reserve(message, %{})
    end
  end

  describe "adjust/4" do
    test "refunds unused credits when actual cost is less than reserved", %{
      organization: organization
    } do
      max_reservation = Credits.max_reservation_credits()
      Billing.add_credits!(organization.id, max_reservation, "Initial credits", authorize?: false)

      message_id = Ash.UUID.generate()
      token_usage = %LangChain.TokenUsage{input: 100, output: 50}
      actual_cost = Credits.calculate_cost(token_usage)

      Billing.reserve_credits!(
        organization.id,
        max_reservation,
        "Test reservation",
        %{reference_type: "message", reference_id: message_id},
        authorize?: false
      )

      reservation = %{
        organization_id: organization.id,
        reserved_amount: max_reservation
      }

      assert :ok = ConsumeCredits.adjust(reservation, token_usage, message_id)

      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == max_reservation - actual_cost
    end

    test "creates ledger entry with message reference", %{organization: organization} do
      max_reservation = Credits.max_reservation_credits()
      Billing.add_credits!(organization.id, max_reservation, "Initial credits", authorize?: false)

      message_id = Ash.UUID.generate()
      token_usage = %LangChain.TokenUsage{input: 100, output: 50}

      Billing.reserve_credits!(
        organization.id,
        max_reservation,
        "Test reservation",
        %{reference_type: "message", reference_id: message_id},
        authorize?: false
      )

      reservation = %{
        organization_id: organization.id,
        reserved_amount: max_reservation
      }

      assert :ok = ConsumeCredits.adjust(reservation, token_usage, message_id)

      entries = Billing.list_credit_entries!(authorize?: false)
      adjustment_entry = Enum.find(entries, &(&1.transaction_type == :reservation_adjustment))

      assert adjustment_entry.reference_type == "message"
      assert adjustment_entry.reference_id == message_id
    end

    test "handles nil token usage by refunding all but minimum", %{organization: organization} do
      max_reservation = Credits.max_reservation_credits()
      Billing.add_credits!(organization.id, max_reservation, "Initial credits", authorize?: false)

      message_id = Ash.UUID.generate()
      actual_cost = Credits.calculate_cost(nil)

      Billing.reserve_credits!(
        organization.id,
        max_reservation,
        "Test reservation",
        %{reference_type: "message", reference_id: message_id},
        authorize?: false
      )

      reservation = %{
        organization_id: organization.id,
        reserved_amount: max_reservation
      }

      assert :ok = ConsumeCredits.adjust(reservation, nil, message_id)

      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == max_reservation - actual_cost
    end

    test "charges overage when actual exceeds reserved", %{
      organization: organization
    } do
      max_reservation = Credits.max_reservation_credits()
      initial_credits = max_reservation * 2
      Billing.add_credits!(organization.id, initial_credits, "Initial credits", authorize?: false)

      message_id = Ash.UUID.generate()

      Billing.reserve_credits!(
        organization.id,
        max_reservation,
        "Test reservation",
        %{reference_type: "message", reference_id: message_id},
        authorize?: false
      )

      reservation = %{
        organization_id: organization.id,
        reserved_amount: max_reservation
      }

      # This produces 180 credits (10000*0.003 + 10000*0.015 = 180)
      # With max_reservation = 500, we need to use more tokens to exceed it
      token_usage = %LangChain.TokenUsage{input: 100_000, output: 20_000}
      actual_cost = Credits.calculate_cost(token_usage)
      assert actual_cost > max_reservation

      overage = actual_cost - max_reservation

      assert :ok = ConsumeCredits.adjust(reservation, token_usage, message_id)

      entries = Billing.list_credit_entries!(authorize?: false)
      usage_entries = Enum.filter(entries, &(&1.transaction_type == :usage))

      # Should have a usage entry for the overage
      assert length(usage_entries) == 1
      overage_entry = List.first(usage_entries)
      assert overage_entry.amount == -overage
      assert overage_entry.reference_id == message_id

      # Balance should be initial_credits - reserved - overage = initial_credits - actual_cost
      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == initial_credits - actual_cost
    end
  end

  describe "refund/2" do
    test "refunds entire reservation", %{organization: organization} do
      max_reservation = Credits.max_reservation_credits()
      Billing.add_credits!(organization.id, max_reservation, "Initial credits", authorize?: false)

      message_id = Ash.UUID.generate()

      Billing.reserve_credits!(
        organization.id,
        max_reservation,
        "Test reservation",
        %{reference_type: "message", reference_id: message_id},
        authorize?: false
      )

      reservation = %{
        organization_id: organization.id,
        reserved_amount: max_reservation
      }

      {:ok, balance_after_reserve} =
        Billing.get_organization_balance(organization.id, authorize?: false)

      assert balance_after_reserve == 0

      assert :ok = ConsumeCredits.refund(reservation, message_id)

      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == max_reservation
    end
  end
end
