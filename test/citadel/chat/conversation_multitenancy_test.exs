defmodule Citadel.Chat.ConversationMultitenancyTest do
  @moduledoc """
  Tests for workspace-based multitenancy isolation in conversations.

  These tests verify that:
  - Conversations are properly scoped to workspaces
  - Users can only access conversations in their workspaces
  - Users cannot access conversations in other workspaces
  - Workspace isolation is enforced consistently
  """
  use Citadel.DataCase, async: true

  alias Citadel.{Accounts, Chat}

  describe "workspace isolation" do
    setup do
      # Create two separate workspaces with different owners
      owner1 = generate(user())
      workspace1 = generate(workspace([], actor: owner1))

      owner2 = generate(user())
      workspace2 = generate(workspace([], actor: owner2))

      {:ok, workspace1: workspace1, owner1: owner1, workspace2: workspace2, owner2: owner2}
    end

    test "users can only see conversations in their workspaces", context do
      %{workspace1: workspace1, owner1: owner1} = context

      # Create conversation in workspace1
      conversation =
        generate(
          conversation(
            [
              workspace_id: workspace1.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Owner1 should be able to see their conversation
      assert {:ok, found_conv} =
               Chat.get_conversation(conversation.id, actor: owner1, tenant: workspace1.id)

      assert found_conv.id == conversation.id
      assert found_conv.workspace_id == workspace1.id
    end

    test "users cannot access conversations in other workspaces", context do
      %{workspace1: workspace1, owner1: owner1, workspace2: workspace2, owner2: owner2} = context

      # Create conversation in workspace1
      conversation =
        generate(
          conversation(
            [
              workspace_id: workspace1.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Owner2 (from different workspace) should NOT be able to see it
      # With multitenancy, wrong tenant returns NotFound/Invalid
      assert_raise Ash.Error.Invalid, fn ->
        Chat.get_conversation!(conversation.id, actor: owner2, tenant: workspace2.id)
      end
    end

    test "creating conversation without workspace raises error", context do
      %{owner1: owner1} = context

      # Attempting to create conversation without workspace_id should fail
      assert_raise Ash.Error.Invalid, fn ->
        Chat.create_conversation!(
          %{title: "Conversation without workspace"},
          actor: owner1
        )
      end
    end

    test "user can access conversations in multiple workspaces they are members of", context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        workspace2: workspace2,
        owner2: owner2
      } = context

      # Create a user who will be a member of both workspaces
      multi_workspace_user = generate(user())

      # Add user to both workspaces
      Accounts.add_workspace_member!(
        multi_workspace_user.id,
        workspace1.id,
        actor: owner1
      )

      Accounts.add_workspace_member!(
        multi_workspace_user.id,
        workspace2.id,
        actor: owner2
      )

      # Create conversations in both workspaces
      conv1 =
        generate(
          conversation(
            [
              workspace_id: workspace1.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      conv2 =
        generate(
          conversation(
            [
              workspace_id: workspace2.id
            ],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      # Multi-workspace user should be able to see conversations from both workspaces
      assert {:ok, found_conv1} =
               Chat.get_conversation(conv1.id, actor: multi_workspace_user, tenant: workspace1.id)

      assert {:ok, found_conv2} =
               Chat.get_conversation(conv2.id, actor: multi_workspace_user, tenant: workspace2.id)

      assert found_conv1.workspace_id == workspace1.id
      assert found_conv2.workspace_id == workspace2.id
    end

    test "listing conversations only returns conversations from accessible workspaces",
         context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        workspace2: workspace2,
        owner2: owner2
      } = context

      # Create conversations in both workspaces
      _conv1 =
        generate(
          conversation(
            [
              workspace_id: workspace1.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      _conv2 =
        generate(
          conversation(
            [
              workspace_id: workspace2.id
            ],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      # Owner1 should only see conversations from workspace1
      convs_for_owner1 =
        Ash.read!(Citadel.Chat.Conversation, actor: owner1, tenant: workspace1.id)

      assert length(convs_for_owner1) == 1

      assert Enum.all?(convs_for_owner1, fn c -> c.workspace_id == workspace1.id end)

      # Owner2 should only see conversations from workspace2
      convs_for_owner2 =
        Ash.read!(Citadel.Chat.Conversation, actor: owner2, tenant: workspace2.id)

      assert length(convs_for_owner2) == 1

      assert Enum.all?(convs_for_owner2, fn c -> c.workspace_id == workspace2.id end)
    end

    test "deleting conversation in different workspace raises forbidden error",
         context do
      %{workspace1: workspace1, owner1: owner1, workspace2: workspace2, owner2: owner2} = context

      # Create conversation in workspace1
      conversation =
        generate(
          conversation(
            [
              workspace_id: workspace1.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Owner2 should not be able to delete conversation from workspace1
      # Gets Forbidden because other user doesn't own the conversation (policy check on user_id)
      assert_raise Ash.Error.Forbidden, fn ->
        Ash.destroy!(conversation, actor: owner2, tenant: workspace2.id)
      end
    end
  end

  describe "workspace membership changes" do
    setup do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      {:ok, workspace: workspace, owner: owner}
    end

    test "leaving workspace removes access to workspace conversations", context do
      %{workspace: workspace, owner: owner} = context

      # Create a member
      member = generate(user())

      membership =
        Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      # Create conversation that member can see
      conversation =
        generate(
          conversation(
            [
              workspace_id: workspace.id
            ],
            actor: owner,
            tenant: workspace.id
          )
        )

      # Member should be able to see the conversation
      assert {:ok, _} =
               Chat.get_conversation(conversation.id, actor: member, tenant: workspace.id)

      # Remove member from workspace
      Accounts.remove_workspace_member!(membership, actor: owner)

      # Member should no longer be able to see the conversation (NotFound)
      assert_raise Ash.Error.Invalid, fn ->
        Chat.get_conversation!(conversation.id, actor: member, tenant: workspace.id)
      end
    end
  end
end
