defmodule Citadel.Billing.Checks.HasSufficientCreditsTest do
  use Citadel.DataCase, async: true

  import Citadel.Generator

  describe "credit check enforcement" do
    test "allows message creation when organization has credits" do
      owner = generate(user())
      org = generate(organization([], actor: owner))
      workspace = generate(workspace([organization_id: org.id], actor: owner))

      # Add credits to the organization
      Citadel.Billing.add_credits!(org.id, 100, "Test credits", authorize?: false)

      # Create a conversation
      conversation =
        generate(conversation([workspace_id: workspace.id], actor: owner, tenant: workspace.id))

      # Message creation should succeed
      message =
        generate(message([conversation_id: conversation.id], actor: owner, tenant: workspace.id))

      assert message.text != nil
      assert message.conversation_id == conversation.id
    end

    test "denies message creation when organization has no credits" do
      owner = generate(user())
      org = generate(organization([], actor: owner))
      workspace = generate(workspace([organization_id: org.id], actor: owner))

      # Create a conversation
      conversation =
        generate(conversation([workspace_id: workspace.id], actor: owner, tenant: workspace.id))

      # Message creation should fail (no credits added)
      assert {:error, %Ash.Error.Forbidden{}} =
               Citadel.Chat.create_message(
                 %{text: "Hello", conversation_id: conversation.id},
                 actor: owner,
                 tenant: workspace.id
               )
    end

    test "allows message creation for workspaces without organization" do
      owner = generate(user())

      # Create a workspace without an organization (legacy)
      workspace = generate(workspace([], actor: owner))

      # Create a conversation
      conversation =
        generate(conversation([workspace_id: workspace.id], actor: owner, tenant: workspace.id))

      # Message creation should succeed (no organization = no credit check)
      message =
        generate(message([conversation_id: conversation.id], actor: owner, tenant: workspace.id))

      assert message.text != nil
    end
  end
end
