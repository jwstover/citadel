defmodule CitadelWeb.ChatLiveTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Citadel.Chat

  describe "feature flag gating" do
    setup :register_and_log_in_user

    test "redirects when ai_chat flag is disabled", %{conn: conn} do
      disable_feature(:ai_chat)

      assert {:error, {:redirect, %{to: "/dashboard", flash: flash}}} =
               live(conn, ~p"/chat")

      assert flash["error"] == "AI Chat is currently unavailable"
    end

    test "allows access when ai_chat flag is enabled", %{conn: conn} do
      enable_feature(:ai_chat)

      assert {:ok, _view, _html} = live(conn, ~p"/chat")
    end

    test "redirects for conversation route when flag is disabled", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      disable_feature(:ai_chat)

      # Create a conversation to test with
      conversation =
        Chat.create_conversation!(
          %{workspace_id: workspace.id},
          actor: user,
          tenant: workspace.id,
          authorize?: false
        )

      assert {:error, {:redirect, %{to: "/dashboard", flash: flash}}} =
               live(conn, ~p"/chat/#{conversation.id}")

      assert flash["error"] == "AI Chat is currently unavailable"
    end
  end
end
