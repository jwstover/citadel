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
      owner1 = generate(user())
      org1 = generate(organization([], actor: owner1))
      workspace1 = generate(workspace([organization_id: org1.id], actor: owner1))

      owner2 = generate(user())
      org2 = generate(organization([], actor: owner2))
      workspace2 = generate(workspace([organization_id: org2.id], actor: owner2))

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
       org1: org1,
       conv1: conv1,
       workspace2: workspace2,
       owner2: owner2,
       org2: org2,
       conv2: conv2}
    end

    test "messages respect workspace boundaries through conversation", context do
      %{conv1: conv1, owner1: owner1, workspace1: workspace1} = context

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

      messages = Ash.read!(Citadel.Chat.Message, actor: owner1)
      refute Enum.empty?(messages)
      assert Enum.any?(messages, fn m -> m.id == message.id end)
    end

    test "cannot access messages from other workspace conversations", context do
      %{conv1: conv1, owner1: owner1, owner2: owner2, workspace1: workspace1} = context

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

      messages_for_owner2 = Ash.read!(Citadel.Chat.Message, actor: owner2)
      refute Enum.any?(messages_for_owner2, fn m -> m.id == message.id end)
    end

    test "users can see messages in all conversations they have access to", context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        org1: org1,
        conv1: conv1,
        workspace2: workspace2,
        owner2: owner2,
        org2: org2,
        conv2: conv2
      } = context

      upgrade_to_pro(org1)
      upgrade_to_pro(org2)

      multi_workspace_user = generate(user())

      add_user_to_workspace(multi_workspace_user.id, workspace1.id, actor: owner1)
      add_user_to_workspace(multi_workspace_user.id, workspace2.id, actor: owner2)

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

      messages = Ash.read!(Citadel.Chat.Message, actor: multi_workspace_user)
      message_ids = Enum.map(messages, & &1.id)

      assert msg1.id in message_ids
      assert msg2.id in message_ids
    end

    test "loading messages requires workspace context through conversation",
         context do
      %{conv1: conv1, owner1: owner1, owner2: owner2, workspace1: workspace1} = context

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

      messages_for_owner2 = Ash.read!(Citadel.Chat.Message, actor: owner2)
      refute Enum.any?(messages_for_owner2, fn m -> m.id == message.id end)
    end

    test "querying messages filtered by conversation respects workspace boundaries",
         context do
      %{conv1: conv1, owner1: owner1, owner2: owner2, workspace1: workspace1} = context

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

      messages_for_owner1 =
        Citadel.Chat.Message
        |> Ash.Query.filter(conversation_id == ^conv1.id)
        |> Ash.read!(actor: owner1)

      assert length(messages_for_owner1) == 3

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
      org = generate(organization([], actor: owner))
      upgrade_to_pro(org)
      workspace = generate(workspace([organization_id: org.id], actor: owner))

      conversation =
        generate(
          conversation(
            [workspace_id: workspace.id],
            actor: owner,
            tenant: workspace.id
          )
        )

      {:ok, workspace: workspace, owner: owner, org: org, conversation: conversation}
    end

    test "leaving workspace removes access to all messages in workspace conversations",
         context do
      %{workspace: workspace, owner: owner, conversation: conversation} = context

      member = generate(user())

      membership = add_user_to_workspace(member.id, workspace.id, actor: owner)

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

      messages = Ash.read!(Citadel.Chat.Message, actor: member)
      message_ids = Enum.map(messages, & &1.id)
      assert msg1.id in message_ids
      assert msg2.id in message_ids

      Accounts.remove_workspace_member!(membership, actor: owner)

      messages_after = Ash.read!(Citadel.Chat.Message, actor: member)
      message_ids_after = Enum.map(messages_after, & &1.id)
      refute msg1.id in message_ids_after
      refute msg2.id in message_ids_after
    end
  end
end
