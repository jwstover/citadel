defmodule CitadelWeb.PreferencesLive.WorkspaceTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Citadel.Generator

  alias Citadel.Accounts
  alias Citadel.Integrations

  describe "handle_params/3" do
    setup :register_and_log_in_user

    test "loads and displays workspace members", %{conn: conn, user: user, workspace: workspace} do
      member = generate(user())
      add_user_to_workspace(member.id, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ to_string(user.email)
      assert html =~ to_string(member.email)
    end

    test "loads and displays pending invitations", %{conn: conn, user: user, workspace: workspace} do
      email = "invited#{System.unique_integer([:positive])}@example.com"
      Accounts.create_invitation!(email, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ email
    end

    test "owner sees workspace management options", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      member = generate(user())
      add_user_to_workspace(member.id, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ "Remove"
      assert html =~ "Invite Member"
    end

    test "member does not see owner options", %{conn: conn, user: user} do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      add_user_to_workspace(user.id, workspace.id, actor: owner)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      refute html =~ "Remove"
    end

    test "redirects when user tries to access workspace they don't belong to", %{
      conn: conn,
      user: _user
    } do
      other_user = generate(user())
      other_workspace = generate(workspace([], actor: other_user))

      assert {:error, {:redirect, %{to: "/preferences", flash: flash}}} =
               live(conn, ~p"/preferences/workspace/#{other_workspace.id}")

      assert flash["error"] == "You do not have access to this workspace"
    end

    test "redirects when workspace does not exist", %{conn: conn, user: _user} do
      fake_id = Ash.UUID.generate()

      assert {:error, {:redirect, %{to: "/preferences", flash: flash}}} =
               live(conn, ~p"/preferences/workspace/#{fake_id}")

      assert flash["error"] == "You do not have access to this workspace"
    end
  end

  describe "render/1" do
    setup :register_and_log_in_user

    test "displays members table with user details", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      member = generate(user())
      add_user_to_workspace(member.id, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ to_string(user.email)
      assert html =~ to_string(member.email)
    end

    test "displays pending invitations table", %{conn: conn, user: user, workspace: workspace} do
      email = "invited#{System.unique_integer([:positive])}@example.com"
      Accounts.create_invitation!(email, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ email
    end
  end

  describe "remove-member event" do
    setup :register_and_log_in_user

    test "owner can remove a member", %{conn: conn, user: user, workspace: workspace} do
      member = generate(user())
      membership = add_user_to_workspace(member.id, workspace.id, actor: user)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      html =
        view
        |> element(~s|[phx-click="remove-member"][phx-value-id="#{membership.id}"]|)
        |> render_click()

      refute html =~ to_string(member.email)

      memberships =
        Accounts.list_workspace_members!(
          actor: user,
          query: [filter: [id: membership.id]]
        )

      assert memberships == []
    end

    test "member does not see remove buttons", %{conn: conn, user: user} do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      org = Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)
      upgrade_to_pro(org)

      add_user_to_workspace(user.id, workspace.id, actor: owner)

      member2 = generate(user())
      add_user_to_workspace(member2.id, workspace.id, actor: owner)

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      refute html =~ "Remove"

      refute has_element?(view, ~s|[phx-click="remove-member"]|)
    end
  end

  describe "revoke-invitation event" do
    setup :register_and_log_in_user

    test "owner can revoke an invitation", %{conn: conn, user: user, workspace: workspace} do
      email = "invited#{System.unique_integer([:positive])}@example.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      html =
        view
        |> element(~s|[phx-click="revoke-invitation"][phx-value-id="#{invitation.id}"]|)
        |> render_click()

      refute html =~ email

      invitations =
        Accounts.list_workspace_invitations!(
          actor: user,
          query: [filter: [id: invitation.id]]
        )

      assert invitations == []
    end

    test "member does not see revoke buttons", %{conn: conn, user: user} do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      add_user_to_workspace(user.id, workspace.id, actor: owner)

      email = "invited#{System.unique_integer([:positive])}@example.com"
      Accounts.create_invitation!(email, workspace.id, actor: owner)

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ email
      refute html =~ "Revoke"

      refute has_element?(view, ~s|[phx-click="revoke-invitation"]|)
    end
  end

  describe "show-invite-modal event" do
    setup :register_and_log_in_user

    test "opens invite modal", %{conn: conn, user: _user, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      html =
        view
        |> element(~s|[phx-click="show-invite-modal"]|)
        |> render_click()

      assert html =~ "modal-open"
    end
  end

  describe "invitation_sent message" do
    setup :register_and_log_in_user

    test "hides modal and refreshes invitations list", %{
      conn: conn,
      user: _user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      view
      |> element(~s|[phx-click="show-invite-modal"]|)
      |> render_click()

      send(view.pid, {:invitation_sent, nil})

      :timer.sleep(50)

      html = render(view)
      refute html =~ "modal-open"
    end
  end

  describe "GitHub integration" do
    setup :register_and_log_in_user

    test "displays integrations card", %{conn: conn, workspace: workspace} do
      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ "Integrations"
      assert html =~ "GitHub"
    end

    test "shows GitHub as not connected when no connection exists", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ "Not connected"
      assert html =~ "Connect"
    end

    test "shows GitHub as connected when connection exists", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      pat = "ghp_test_token_#{System.unique_integer([:positive])}"
      Integrations.create_github_connection!(pat, tenant: workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ "Connected"
      assert html =~ "Disconnect"
    end

    test "owner sees Connect button when not connected", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert has_element?(view, ~s|[phx-click="show-github-modal"]|)
    end

    test "owner sees Disconnect button when connected", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      pat = "ghp_test_token_#{System.unique_integer([:positive])}"
      Integrations.create_github_connection!(pat, tenant: workspace.id, actor: user)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert has_element?(view, ~s|[phx-click="show-disconnect-confirmation"]|)
    end

    test "member does not see Connect button", %{conn: conn, user: user} do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))
      add_user_to_workspace(user.id, workspace.id, actor: owner)

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ "Integrations"
      assert html =~ "GitHub"
      refute has_element?(view, ~s|[phx-click="show-github-modal"]|)
    end

    test "member sees badge instead of buttons when connected", %{conn: conn, user: user} do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))
      add_user_to_workspace(user.id, workspace.id, actor: owner)

      pat = "ghp_test_token_#{System.unique_integer([:positive])}"
      Integrations.create_github_connection!(pat, tenant: workspace.id, actor: owner)

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ "badge-success"
      refute has_element?(view, ~s|[phx-click="show-disconnect-confirmation"]|)
    end

    test "clicking Connect opens GitHub modal", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      html =
        view
        |> element(~s|[phx-click="show-github-modal"]|)
        |> render_click()

      assert html =~ "Connect GitHub"
      assert html =~ "Personal Access Token"
    end

    test "clicking Disconnect opens confirmation modal", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      pat = "ghp_test_token_#{System.unique_integer([:positive])}"
      Integrations.create_github_connection!(pat, tenant: workspace.id, actor: user)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      html =
        view
        |> element(~s|[phx-click="show-disconnect-confirmation"]|)
        |> render_click()

      assert html =~ "Disconnect GitHub"
      assert html =~ "Are you sure"
    end

    test "confirming disconnect removes the connection", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      pat = "ghp_test_token_#{System.unique_integer([:positive])}"
      Integrations.create_github_connection!(pat, tenant: workspace.id, actor: user)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      view
      |> element(~s|[phx-click="show-disconnect-confirmation"]|)
      |> render_click()

      html =
        view
        |> element(~s|[phx-click="confirm-disconnect-github"]|)
        |> render_click()

      assert html =~ "Not connected"
      assert html =~ "Connect"

      result =
        Integrations.get_workspace_github_connection(workspace.id,
          tenant: workspace.id,
          actor: user,
          not_found_error?: false
        )

      assert result == {:ok, nil}
    end

    test "canceling disconnect closes modal", %{conn: conn, user: user, workspace: workspace} do
      pat = "ghp_test_token_#{System.unique_integer([:positive])}"
      Integrations.create_github_connection!(pat, tenant: workspace.id, actor: user)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      view
      |> element(~s|[phx-click="show-disconnect-confirmation"]|)
      |> render_click()

      html =
        view
        |> element(~s|button.btn-ghost:not(.btn-circle)[phx-click="cancel-disconnect-github"]|)
        |> render_click()

      refute html =~ "Are you sure"
      assert html =~ "Connected"
    end
  end
end
