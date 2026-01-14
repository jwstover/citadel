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
      owner1 = generate(user())
      org1 = generate(organization([], actor: owner1))
      workspace1 = generate(workspace([organization_id: org1.id], actor: owner1))

      owner2 = generate(user())
      org2 = generate(organization([], actor: owner2))
      workspace2 = generate(workspace([organization_id: org2.id], actor: owner2))

      {:ok,
       workspace1: workspace1,
       owner1: owner1,
       org1: org1,
       workspace2: workspace2,
       owner2: owner2,
       org2: org2}
    end

    test "users can only see conversations in their workspaces", context do
      %{workspace1: workspace1, owner1: owner1} = context

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

      assert {:ok, found_conv} =
               Chat.get_conversation(conversation.id, actor: owner1, tenant: workspace1.id)

      assert found_conv.id == conversation.id
      assert found_conv.workspace_id == workspace1.id
    end

    test "users cannot access conversations in other workspaces", context do
      %{workspace1: workspace1, owner1: owner1, workspace2: workspace2, owner2: owner2} = context

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

      assert_raise Ash.Error.Invalid, fn ->
        Chat.get_conversation!(conversation.id, actor: owner2, tenant: workspace2.id)
      end
    end

    test "creating conversation without workspace raises error", context do
      %{owner1: owner1} = context

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
        org1: org1,
        workspace2: workspace2,
        owner2: owner2,
        org2: org2
      } = context

      upgrade_to_pro(org1)
      upgrade_to_pro(org2)

      multi_workspace_user = generate(user())

      add_user_to_workspace(multi_workspace_user.id, workspace1.id, actor: owner1)
      add_user_to_workspace(multi_workspace_user.id, workspace2.id, actor: owner2)

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

      convs_for_owner1 =
        Ash.read!(Citadel.Chat.Conversation, actor: owner1, tenant: workspace1.id)

      assert length(convs_for_owner1) == 1

      assert Enum.all?(convs_for_owner1, fn c -> c.workspace_id == workspace1.id end)

      convs_for_owner2 =
        Ash.read!(Citadel.Chat.Conversation, actor: owner2, tenant: workspace2.id)

      assert length(convs_for_owner2) == 1

      assert Enum.all?(convs_for_owner2, fn c -> c.workspace_id == workspace2.id end)
    end

    test "deleting conversation in different workspace raises forbidden error",
         context do
      %{workspace1: workspace1, owner1: owner1, workspace2: workspace2, owner2: owner2} = context

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

      assert_raise Ash.Error.Forbidden, fn ->
        Ash.destroy!(conversation, actor: owner2, tenant: workspace2.id)
      end
    end
  end

  describe "workspace membership changes" do
    setup do
      owner = generate(user())
      org = generate(organization([], actor: owner))
      upgrade_to_pro(org)
      workspace = generate(workspace([organization_id: org.id], actor: owner))

      {:ok, workspace: workspace, owner: owner, org: org}
    end

    test "leaving workspace removes access to workspace conversations", context do
      %{workspace: workspace, owner: owner} = context

      member = generate(user())

      membership = add_user_to_workspace(member.id, workspace.id, actor: owner)

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

      assert {:ok, _} =
               Chat.get_conversation(conversation.id, actor: member, tenant: workspace.id)

      Accounts.remove_workspace_member!(membership, actor: owner)

      assert_raise Ash.Error.Invalid, fn ->
        Chat.get_conversation!(conversation.id, actor: member, tenant: workspace.id)
      end
    end
  end
end
