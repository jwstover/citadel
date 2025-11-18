defmodule Citadel.Chat.PubSubWorkspaceIsolationTest do
  @moduledoc """
  Tests for workspace isolation in PubSub real-time updates.

  These tests verify that:
  - Conversation updates are only broadcast to the workspace's topic
  - Users in different workspaces don't receive each other's updates
  - Message updates are properly isolated by conversation (and thus workspace)
  - PubSub topics correctly use workspace_id for conversations
  """
  use Citadel.DataCase, async: true

  alias Citadel.Accounts

  setup do
    # Create two separate workspaces
    owner1 = generate(user())
    workspace1 = generate(workspace([], actor: owner1))

    owner2 = generate(user())
    workspace2 = generate(workspace([], actor: owner2))

    # Subscribe to both workspace topics to monitor broadcasts
    CitadelWeb.Endpoint.subscribe("chat:conversations:#{workspace1.id}")
    CitadelWeb.Endpoint.subscribe("chat:conversations:#{workspace2.id}")

    {:ok, workspace1: workspace1, owner1: owner1, workspace2: workspace2, owner2: owner2}
  end

  describe "conversation PubSub isolation" do
    test "creating conversation only broadcasts to its workspace topic", context do
      %{workspace1: workspace1, owner1: owner1, workspace2: workspace2} = context

      # Create conversation in workspace1
      conversation =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Should receive broadcast on workspace1 topic
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> topic_workspace_id,
        event: "create",
        payload: ^conversation
      }

      assert topic_workspace_id == workspace1.id

      # Should NOT receive broadcast on workspace2 topic
      workspace2_topic = "chat:conversations:#{workspace2.id}"

      refute_receive %Phoenix.Socket.Broadcast{
        topic: ^workspace2_topic
      }
    end

    test "creating multiple conversations in same workspace uses same topic", context do
      %{workspace1: workspace1, owner1: owner1} = context

      # Create first conversation in workspace1
      conv1 =
        generate(
          conversation(
            [workspace_id: workspace1.id, title: "First Conversation"],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Should receive on workspace1 topic
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> ws1_id_first,
        event: "create",
        payload: ^conv1
      }

      assert ws1_id_first == workspace1.id

      # Create second conversation in same workspace
      conv2 =
        generate(
          conversation(
            [workspace_id: workspace1.id, title: "Second Conversation"],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Should receive on the SAME workspace1 topic
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> ws1_id_second,
        event: "create",
        payload: ^conv2
      }

      assert ws1_id_second == workspace1.id
      assert ws1_id_first == ws1_id_second
    end

    test "conversations in different workspaces use different topics", context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        workspace2: workspace2,
        owner2: owner2
      } = context

      # Create conversation in workspace1
      conv1 =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Should receive on workspace1 topic
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> ws1_id,
        event: "create",
        payload: ^conv1
      }

      assert ws1_id == workspace1.id

      # Create conversation in workspace2
      conv2 =
        generate(
          conversation(
            [workspace_id: workspace2.id],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      # Should receive on workspace2 topic
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> ws2_id,
        event: "create",
        payload: ^conv2
      }

      assert ws2_id == workspace2.id
      assert ws2_id != ws1_id
    end

    test "member added to workspace receives conversation updates", context do
      %{workspace1: workspace1, owner1: owner1} = context

      # Create a new member
      member = generate(user())

      # Add member to workspace1
      Accounts.add_workspace_member!(member.id, workspace1.id, actor: owner1)

      # Member subscribes to workspace1 topic (simulating LiveView mount)
      CitadelWeb.Endpoint.subscribe("chat:conversations:#{workspace1.id}")

      # Create conversation in workspace1
      conversation =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Member should receive the broadcast (they're subscribed to the same topic)
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> _,
        payload: ^conversation
      }
    end
  end

  describe "message PubSub isolation" do
    test "messages are broadcast to conversation-specific topics", context do
      %{workspace1: workspace1, owner1: owner1} = context

      # Create conversation in workspace1
      conversation =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Clear the conversation create broadcast
      assert_receive %Phoenix.Socket.Broadcast{event: "create"}

      # Subscribe to this conversation's message topic
      CitadelWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")

      # Create a message in the conversation
      message =
        generate(
          message(
            [conversation_id: conversation.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Should receive message broadcast on conversation topic
      # Note: payload is transformed to only include id, text, source
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:messages:" <> conv_id,
        event: "create",
        payload: %{id: message_id, text: text, source: :user}
      }

      assert conv_id == conversation.id
      assert message_id == message.id
      assert text == message.text
    end

    test "messages in different conversations don't cross-contaminate", context do
      %{workspace1: workspace1, owner1: owner1} = context

      # Create two conversations in the same workspace
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
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Clear conversation create broadcasts
      assert_receive %Phoenix.Socket.Broadcast{event: "create"}
      assert_receive %Phoenix.Socket.Broadcast{event: "create"}

      # Subscribe to conv1's message topic only
      CitadelWeb.Endpoint.subscribe("chat:messages:#{conv1.id}")

      # Create message in conv2
      message2 =
        generate(
          message(
            [conversation_id: conv2.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Should NOT receive message from conv2 (not subscribed to that topic)
      refute_receive %Phoenix.Socket.Broadcast{
        topic: "chat:messages:" <> _,
        payload: ^message2
      }
    end

    test "messages inherit workspace isolation through conversation", context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        workspace2: workspace2,
        owner2: owner2
      } = context

      # Create conversations in both workspaces
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

      # Clear conversation broadcasts
      assert_receive %Phoenix.Socket.Broadcast{event: "create"}
      assert_receive %Phoenix.Socket.Broadcast{event: "create"}

      # Subscribe to both conversation message topics
      CitadelWeb.Endpoint.subscribe("chat:messages:#{conv1.id}")
      CitadelWeb.Endpoint.subscribe("chat:messages:#{conv2.id}")

      # Create message in conv1 (workspace1)
      msg1 =
        generate(
          message(
            [conversation_id: conv1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Should receive on conv1 topic (transformed payload)
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:messages:" <> c1_id,
        payload: %{id: msg1_id, text: msg1_text, source: :user}
      }

      assert c1_id == conv1.id
      assert msg1_id == msg1.id
      assert msg1_text == msg1.text

      # Create message in conv2 (workspace2)
      msg2 =
        generate(
          message(
            [conversation_id: conv2.id],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      # Should receive on conv2 topic (different from conv1, transformed payload)
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:messages:" <> c2_id,
        payload: %{id: msg2_id, text: msg2_text, source: :user}
      }

      assert c2_id == conv2.id
      assert msg2_id == msg2.id
      assert msg2_text == msg2.text
      assert c2_id != c1_id
    end
  end

  describe "cross-workspace isolation verification" do
    test "user switching workspaces requires changing subscriptions", context do
      %{
        workspace1: workspace1,
        workspace2: workspace2,
        owner1: owner1,
        owner2: owner2
      } = context

      # Create a user who is a member of both workspaces
      multi_user = generate(user())

      Accounts.add_workspace_member!(multi_user.id, workspace1.id, actor: owner1)
      Accounts.add_workspace_member!(multi_user.id, workspace2.id, actor: owner2)

      # User starts by subscribing to ONLY workspace1 (simulating LiveView mount)
      # First, unsubscribe from workspace2 (subscribed in setup)
      CitadelWeb.Endpoint.unsubscribe("chat:conversations:#{workspace2.id}")

      # Already subscribed to workspace1 from setup, so we're good there

      # Create conversation in workspace1
      conv1 =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # User receives update (subscribed to workspace1)
      assert_receive %Phoenix.Socket.Broadcast{
        payload: ^conv1
      }

      # Create conversation in workspace2 BEFORE subscribing
      conv2 =
        generate(
          conversation(
            [workspace_id: workspace2.id],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      # User does NOT receive update (not subscribed to workspace2)
      refute_receive %Phoenix.Socket.Broadcast{
        payload: ^conv2
      }

      # User switches to workspace2 (unsubscribe from ws1, subscribe to ws2)
      CitadelWeb.Endpoint.unsubscribe("chat:conversations:#{workspace1.id}")
      CitadelWeb.Endpoint.subscribe("chat:conversations:#{workspace2.id}")

      # Now create another conversation in workspace2
      conv3 =
        generate(
          conversation(
            [workspace_id: workspace2.id],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      # User DOES receive this update (now subscribed to workspace2)
      assert_receive %Phoenix.Socket.Broadcast{
        payload: ^conv3
      }

      # Create conversation in workspace1 while subscribed to workspace2
      conv4 =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # User does NOT receive workspace1 update (unsubscribed from workspace1)
      refute_receive %Phoenix.Socket.Broadcast{
        payload: ^conv4
      }
    end
  end
end
