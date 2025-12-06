defmodule Citadel.Chat.MessageMultitenancyTest do
  @moduledoc """
  Tests for workspace-based multitenancy isolation in messages.

  These tests verify that:
  - Messages inherit workspace context through their conversation
  - Users can only access messages in conversations within their workspaces
  - Users cannot access messages from other workspace conversations
  - Workspace isolation is enforced via conversation relationships
  """
  use Citadel.DataCase, async: true

  alias Citadel.Accounts

  require Ash.Query

  describe "workspace isolation via conversation" do
    setup do
      # Create two separate workspaces with different owners
      owner1 = generate(user())
      workspace1 = generate(workspace([], actor: owner1))

      owner2 = generate(user())
      workspace2 = generate(workspace([], actor: owner2))

      # Create conversations in each workspace
      conv1 =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      conv2 =
        generate(
          conversation(
            [workspace_id: workspace2.id],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      {:ok,
       workspace1: workspace1,
       owner1: owner1,
       conv1: conv1,
       workspace2: workspace2,
       owner2: owner2,
       conv2: conv2}
    end

    test "messages respect workspace boundaries through conversation", context do
      %{conv1: conv1, owner1: owner1, workspace1: workspace1} = context

      # Create message in workspace1's conversation
      message =
        generate(
          message(
            [
              text: "Hello from workspace 1",
              conversation_id: conv1.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Owner1 should be able to see their message
      messages = Ash.read!(Citadel.Chat.Message, actor: owner1)
      refute Enum.empty?(messages)
      assert Enum.any?(messages, fn m -> m.id == message.id end)
    end

    test "cannot access messages from other workspace conversations", context do
      %{conv1: conv1, owner1: owner1, owner2: owner2, workspace1: workspace1} = context

      # Create message in workspace1's conversation
      message =
        generate(
          message(
            [
              text: "Private message in workspace 1",
              conversation_id: conv1.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Owner2 should NOT be able to see messages from workspace1
      messages_for_owner2 = Ash.read!(Citadel.Chat.Message, actor: owner2)
      refute Enum.any?(messages_for_owner2, fn m -> m.id == message.id end)
    end

    test "users can see messages in all conversations they have access to", context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        conv1: conv1,
        workspace2: workspace2,
        owner2: owner2,
        conv2: conv2
      } = context

      # Create a user who is a member of both workspaces
      multi_workspace_user = generate(user())

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

      # Create messages in both workspace conversations
      msg1 =
        generate(
          message(
            [
              text: "Message in workspace 1",
              conversation_id: conv1.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      msg2 =
        generate(
          message(
            [
              text: "Message in workspace 2",
              conversation_id: conv2.id
            ],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      # Multi-workspace user should see messages from both
      messages = Ash.read!(Citadel.Chat.Message, actor: multi_workspace_user)
      message_ids = Enum.map(messages, & &1.id)

      assert msg1.id in message_ids
      assert msg2.id in message_ids
    end

    test "loading messages requires workspace context through conversation",
         context do
      %{conv1: conv1, owner1: owner1, owner2: owner2, workspace1: workspace1} = context

      # Create message in workspace1's conversation
      message =
        generate(
          message(
            [
              text: "Test message",
              conversation_id: conv1.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Loading message directly should fail for owner2
      # Note: This depends on how your read action is configured
      # Messages inherit authorization through conversation
      messages_for_owner2 = Ash.read!(Citadel.Chat.Message, actor: owner2)
      refute Enum.any?(messages_for_owner2, fn m -> m.id == message.id end)
    end

    test "querying messages filtered by conversation respects workspace boundaries",
         context do
      %{conv1: conv1, owner1: owner1, owner2: owner2, workspace1: workspace1} = context

      # Create multiple messages in workspace1's conversation
      for i <- 1..3 do
        generate(
          message(
            [
              text: "Message #{i}",
              conversation_id: conv1.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )
      end

      # Owner1 should see all messages in their conversation
      messages_for_owner1 =
        Citadel.Chat.Message
        |> Ash.Query.filter(conversation_id == ^conv1.id)
        |> Ash.read!(actor: owner1)

      assert length(messages_for_owner1) == 3

      # Owner2 should not see any messages from workspace1's conversation
      messages_for_owner2 =
        Citadel.Chat.Message
        |> Ash.Query.filter(conversation_id == ^conv1.id)
        |> Ash.read!(actor: owner2)

      assert messages_for_owner2 == []
    end
  end

  describe "workspace membership changes affect message access" do
    setup do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      conversation =
        generate(
          conversation(
            [workspace_id: workspace.id],
            actor: owner,
            tenant: workspace.id
          )
        )

      {:ok, workspace: workspace, owner: owner, conversation: conversation}
    end

    test "leaving workspace removes access to all messages in workspace conversations",
         context do
      %{workspace: workspace, owner: owner, conversation: conversation} = context

      # Create a member
      member = generate(user())

      membership =
        Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      # Create messages in workspace conversation
      msg1 =
        generate(
          message(
            [
              text: "Message 1",
              conversation_id: conversation.id
            ],
            actor: owner,
            tenant: workspace.id
          )
        )

      msg2 =
        generate(
          message(
            [
              text: "Message 2",
              conversation_id: conversation.id
            ],
            actor: member,
            tenant: workspace.id
          )
        )

      # Member should be able to see both messages
      messages = Ash.read!(Citadel.Chat.Message, actor: member)
      message_ids = Enum.map(messages, & &1.id)
      assert msg1.id in message_ids
      assert msg2.id in message_ids

      # Remove member from workspace
      Accounts.remove_workspace_member!(membership, actor: owner)

      # Member should no longer see any messages from that workspace
      messages_after = Ash.read!(Citadel.Chat.Message, actor: member)
      message_ids_after = Enum.map(messages_after, & &1.id)
      refute msg1.id in message_ids_after
      refute msg2.id in message_ids_after
    end
  end
end
