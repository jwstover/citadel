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

  setup do
    owner1 = generate(user())
    org1 = generate(organization([], actor: owner1))
    workspace1 = generate(workspace([organization_id: org1.id], actor: owner1))

    owner2 = generate(user())
    org2 = generate(organization([], actor: owner2))
    workspace2 = generate(workspace([organization_id: org2.id], actor: owner2))

    CitadelWeb.Endpoint.subscribe("chat:conversations:#{workspace1.id}")
    CitadelWeb.Endpoint.subscribe("chat:conversations:#{workspace2.id}")

    {:ok,
     workspace1: workspace1,
     owner1: owner1,
     org1: org1,
     workspace2: workspace2,
     owner2: owner2,
     org2: org2}
  end

  describe "conversation PubSub isolation" do
    test "creating conversation only broadcasts to its workspace topic", context do
      %{workspace1: workspace1, owner1: owner1, workspace2: workspace2} = context

      conversation =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> topic_workspace_id,
        event: "create",
        payload: ^conversation
      }

      assert topic_workspace_id == workspace1.id

      workspace2_topic = "chat:conversations:#{workspace2.id}"

      refute_receive %Phoenix.Socket.Broadcast{
        topic: ^workspace2_topic
      }
    end

    test "creating multiple conversations in same workspace uses same topic", context do
      %{workspace1: workspace1, owner1: owner1} = context

      conv1 =
        generate(
          conversation(
            [workspace_id: workspace1.id, title: "First Conversation"],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> ws1_id_first,
        event: "create",
        payload: ^conv1
      }

      assert ws1_id_first == workspace1.id

      conv2 =
        generate(
          conversation(
            [workspace_id: workspace1.id, title: "Second Conversation"],
            actor: owner1,
            tenant: workspace1.id
          )
        )

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

      conv1 =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> ws1_id,
        event: "create",
        payload: ^conv1
      }

      assert ws1_id == workspace1.id

      conv2 =
        generate(
          conversation(
            [workspace_id: workspace2.id],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> ws2_id,
        event: "create",
        payload: ^conv2
      }

      assert ws2_id == workspace2.id
      assert ws2_id != ws1_id
    end

    test "member added to workspace receives conversation updates", context do
      %{workspace1: workspace1, owner1: owner1, org1: org1} = context

      member = generate(user())

      upgrade_to_pro(org1)
      add_user_to_workspace(member.id, workspace1.id, actor: owner1)

      CitadelWeb.Endpoint.subscribe("chat:conversations:#{workspace1.id}")

      conversation =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:conversations:" <> _,
        payload: ^conversation
      }
    end
  end

  describe "message PubSub isolation" do
    test "messages are broadcast to conversation-specific topics", context do
      %{workspace1: workspace1, owner1: owner1} = context

      conversation =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{event: "create"}

      CitadelWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")

      message =
        generate(
          message(
            [conversation_id: conversation.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

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

      assert_receive %Phoenix.Socket.Broadcast{event: "create"}
      assert_receive %Phoenix.Socket.Broadcast{event: "create"}

      CitadelWeb.Endpoint.subscribe("chat:messages:#{conv1.id}")

      message2 =
        generate(
          message(
            [conversation_id: conv2.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

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

      assert_receive %Phoenix.Socket.Broadcast{event: "create"}
      assert_receive %Phoenix.Socket.Broadcast{event: "create"}

      CitadelWeb.Endpoint.subscribe("chat:messages:#{conv1.id}")
      CitadelWeb.Endpoint.subscribe("chat:messages:#{conv2.id}")

      msg1 =
        generate(
          message(
            [conversation_id: conv1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "chat:messages:" <> c1_id,
        payload: %{id: msg1_id, text: msg1_text, source: :user}
      }

      assert c1_id == conv1.id
      assert msg1_id == msg1.id
      assert msg1_text == msg1.text

      msg2 =
        generate(
          message(
            [conversation_id: conv2.id],
            actor: owner2,
            tenant: workspace2.id
          )
        )

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
        owner2: owner2,
        org1: org1,
        org2: org2
      } = context

      upgrade_to_pro(org1)
      upgrade_to_pro(org2)

      multi_user = generate(user())

      add_user_to_workspace(multi_user.id, workspace1.id, actor: owner1)
      add_user_to_workspace(multi_user.id, workspace2.id, actor: owner2)

      CitadelWeb.Endpoint.unsubscribe("chat:conversations:#{workspace2.id}")

      conv1 =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        payload: ^conv1
      }

      conv2 =
        generate(
          conversation(
            [workspace_id: workspace2.id],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      refute_receive %Phoenix.Socket.Broadcast{
        payload: ^conv2
      }

      CitadelWeb.Endpoint.unsubscribe("chat:conversations:#{workspace1.id}")
      CitadelWeb.Endpoint.subscribe("chat:conversations:#{workspace2.id}")

      conv3 =
        generate(
          conversation(
            [workspace_id: workspace2.id],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        payload: ^conv3
      }

      conv4 =
        generate(
          conversation(
            [workspace_id: workspace1.id],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      refute_receive %Phoenix.Socket.Broadcast{
        payload: ^conv4
      }
    end
  end
end
