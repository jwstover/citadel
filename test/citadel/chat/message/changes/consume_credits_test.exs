defmodule Citadel.Chat.Message.Changes.ConsumeCreditsTest do
  use Citadel.DataCase, async: true

  alias Citadel.Billing
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

    test "returns error when workspace has no organization", %{owner: owner} do
      # Create a workspace without an organization (legacy)
      workspace_without_org = generate(workspace([organization_id: nil], actor: owner))

      conversation =
        generate(
          conversation(
            [workspace_id: workspace_without_org.id],
            actor: owner,
            tenant: workspace_without_org.id
          )
        )

      message =
        generate(
          message(
            [conversation_id: conversation.id],
            actor: owner,
            tenant: workspace_without_org.id,
            authorize?: false
          )
        )

      assert {:error, :no_organization} = ConsumeCredits.resolve_organization_id(message, %{})
    end
  end

  describe "pre_check/2" do
    test "returns ok with org_id when credits are sufficient", %{
      owner: owner,
      organization: organization,
      workspace: workspace,
      conversation: conversation
    } do
      # Add credits
      Billing.add_credits!(organization.id, 500, "Initial credits", authorize?: false)

      message =
        generate(
          message(
            [conversation_id: conversation.id],
            actor: owner,
            tenant: workspace.id,
            authorize?: false
          )
        )

      assert {:ok, org_id} = ConsumeCredits.pre_check(message, %{})
      assert org_id == organization.id
    end

    test "returns error when credits are insufficient", %{
      owner: owner,
      organization: _organization,
      workspace: workspace,
      conversation: conversation
    } do
      # No credits added

      message =
        generate(
          message(
            [conversation_id: conversation.id],
            actor: owner,
            tenant: workspace.id,
            authorize?: false
          )
        )

      assert {:error, :insufficient_credits} = ConsumeCredits.pre_check(message, %{})
    end

    test "returns error when workspace has no organization", %{owner: owner} do
      workspace_without_org = generate(workspace([organization_id: nil], actor: owner))

      conversation =
        generate(
          conversation(
            [workspace_id: workspace_without_org.id],
            actor: owner,
            tenant: workspace_without_org.id
          )
        )

      message =
        generate(
          message(
            [conversation_id: conversation.id],
            actor: owner,
            tenant: workspace_without_org.id,
            authorize?: false
          )
        )

      assert {:error, :no_organization} = ConsumeCredits.pre_check(message, %{})
    end
  end

  describe "post_charge/4" do
    test "deducts credits based on token usage", %{organization: organization} do
      # Add credits
      Billing.add_credits!(organization.id, 500, "Initial credits", authorize?: false)

      message_id = Ash.UUID.generate()
      token_usage = %LangChain.TokenUsage{input: 1000, output: 500}

      assert :ok = ConsumeCredits.post_charge(organization.id, token_usage, message_id)

      # Check balance decreased (11 credits used based on default rates)
      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == 489
    end

    test "creates ledger entry with message reference", %{organization: organization} do
      Billing.add_credits!(organization.id, 500, "Initial credits", authorize?: false)

      message_id = Ash.UUID.generate()
      token_usage = %LangChain.TokenUsage{input: 100, output: 50}

      assert :ok = ConsumeCredits.post_charge(organization.id, token_usage, message_id)

      # Check ledger entry was created with reference
      entries = Billing.list_credit_entries!(authorize?: false)
      usage_entry = Enum.find(entries, &(&1.transaction_type == :usage))

      assert usage_entry.reference_type == "message"
      assert usage_entry.reference_id == message_id
    end

    test "handles nil token usage gracefully", %{organization: organization} do
      Billing.add_credits!(organization.id, 500, "Initial credits", authorize?: false)

      message_id = Ash.UUID.generate()

      assert :ok = ConsumeCredits.post_charge(organization.id, nil, message_id)

      # Should deduct minimum (1 credit)
      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == 499
    end

    test "handles insufficient credits error gracefully", %{organization: organization} do
      # No credits added
      message_id = Ash.UUID.generate()
      token_usage = %LangChain.TokenUsage{input: 1000, output: 500}

      # Should not raise, just return :ok (error is logged)
      assert :ok = ConsumeCredits.post_charge(organization.id, token_usage, message_id)
    end
  end
end
