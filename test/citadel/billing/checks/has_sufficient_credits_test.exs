defmodule Citadel.Billing.Checks.HasSufficientCreditsTest do
  use Citadel.DataCase, async: true

  import Citadel.Generator

  describe "organization and subscription validation" do
    test "allows message creation when organization has active subscription" do
      owner = generate(user())
      org = generate(organization([], actor: owner))
      workspace = generate(workspace([organization_id: org.id], actor: owner))

      # Add credits to the organization
      Citadel.Billing.add_credits!(org.id, 100, "Test credits", authorize?: false)

      # Create a conversation
      conversation =
        generate(conversation([workspace_id: workspace.id], actor: owner, tenant: workspace.id))

      # Message creation should succeed (org exists with active subscription)
      message =
        generate(message([conversation_id: conversation.id], actor: owner, tenant: workspace.id))

      assert message.text != nil
      assert message.conversation_id == conversation.id
    end

    test "allows message creation when organization has zero credits (balance checked atomically during AI call)" do
      owner = generate(user())
      org = generate(organization([], actor: owner))
      workspace = generate(workspace([organization_id: org.id], actor: owner))

      # Create a conversation (no credits added)
      conversation =
        generate(conversation([workspace_id: workspace.id], actor: owner, tenant: workspace.id))

      # Message creation should succeed because:
      # 1. Policy only checks org exists with subscription (not credit balance)
      # 2. Credit balance is validated atomically during ConsumeCredits.reserve()
      #    which happens in the AI response flow, preventing race conditions
      message =
        generate(message([conversation_id: conversation.id], actor: owner, tenant: workspace.id))

      assert message.text != nil
      assert message.conversation_id == conversation.id
    end

    test "denies message creation when subscription is not active" do
      owner = generate(user())
      org = generate(organization([], actor: owner))
      workspace = generate(workspace([organization_id: org.id], actor: owner))

      # Cancel the subscription
      subscription =
        Citadel.Billing.get_subscription_by_organization!(org.id, authorize?: false)

      Citadel.Billing.cancel_subscription!(subscription, authorize?: false)

      # Create a conversation
      conversation =
        generate(conversation([workspace_id: workspace.id], actor: owner, tenant: workspace.id))

      # Message creation should fail (subscription not active)
      assert {:error, %Ash.Error.Forbidden{}} =
               Citadel.Chat.create_message(
                 %{text: "Hello", conversation_id: conversation.id},
                 actor: owner,
                 tenant: workspace.id
               )
    end
  end
end
