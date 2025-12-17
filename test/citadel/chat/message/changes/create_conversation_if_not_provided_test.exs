defmodule Citadel.Chat.Message.Changes.CreateConversationIfNotProvidedTest do
  use Citadel.DataCase, async: true

  import Citadel.Generator

  describe "CreateConversationIfNotProvided" do
    test "creates a conversation when none is provided" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      message =
        Citadel.Chat.create_message!(%{text: "Hello!"},
          actor: user,
          tenant: workspace.id
        )

      assert message.conversation_id != nil

      conversation =
        Citadel.Chat.get_conversation!(message.conversation_id,
          actor: user,
          tenant: workspace.id
        )

      assert conversation.workspace_id == workspace.id
      assert conversation.user_id == user.id
    end

    test "uses provided conversation when one exists" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      existing_conversation =
        generate(
          conversation(
            [workspace_id: workspace.id],
            actor: user,
            tenant: workspace.id
          )
        )

      message =
        Citadel.Chat.create_message!(
          %{text: "Hello!", conversation_id: existing_conversation.id},
          actor: user,
          tenant: workspace.id
        )

      assert message.conversation_id == existing_conversation.id
    end

    test "validates conversation exists and is accessible" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      other_user = generate(user())
      other_workspace = generate(workspace([], actor: other_user))

      other_conversation =
        generate(
          conversation(
            [workspace_id: other_workspace.id],
            actor: other_user,
            tenant: other_workspace.id
          )
        )

      assert {:error, %Ash.Error.Invalid{}} =
               Citadel.Chat.create_message(
                 %{text: "Hello!", conversation_id: other_conversation.id},
                 actor: user,
                 tenant: workspace.id
               )
    end

    test "returns error for non-existent conversation" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))
      fake_uuid = Ash.UUID.generate()

      assert {:error, %Ash.Error.Invalid{}} =
               Citadel.Chat.create_message(
                 %{text: "Hello!", conversation_id: fake_uuid},
                 actor: user,
                 tenant: workspace.id
               )
    end

    test "workspace member can create message that auto-creates conversation" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      member = generate(user())

      _membership =
        generate(
          workspace_membership(
            [user_id: member.id, workspace_id: workspace.id],
            actor: owner
          )
        )

      message =
        Citadel.Chat.create_message!(%{text: "Hello from member!"},
          actor: member,
          tenant: workspace.id
        )

      assert message.conversation_id != nil

      conversation =
        Citadel.Chat.get_conversation!(message.conversation_id,
          actor: member,
          tenant: workspace.id
        )

      assert conversation.workspace_id == workspace.id
      assert conversation.user_id == member.id
    end
  end
end
