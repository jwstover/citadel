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
      Accounts.add_workspace_member!(member.id, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Should display both users' emails in the members table
      assert html =~ to_string(user.email)
      assert html =~ to_string(member.email)
    end

    test "loads and displays pending invitations", %{conn: conn, user: user, workspace: workspace} do
      # Create an invitation
      email = "invited#{System.unique_integer([:positive])}@example.com"
      Accounts.create_invitation!(email, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Should display the invitation email
      assert html =~ email
    end

    test "owner sees workspace management options", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      # Add a member so the Remove button appears (owner can't remove themselves)
      member = generate(user())
      Accounts.add_workspace_member!(member.id, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Owner should see remove and invite buttons
      assert html =~ "Remove"
      assert html =~ "Invite Member"
    end

    test "member does not see owner options", %{conn: conn, user: user} do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      # Add current user as member
      Accounts.add_workspace_member!(user.id, workspace.id, actor: owner)

      # Log in as member
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Member should not see remove buttons for other members
      refute html =~ "Remove"
    end

    test "redirects when user tries to access workspace they don't belong to", %{
      conn: conn,
      user: _user
    } do
      # Create a workspace owned by someone else
      other_user = generate(user())
      other_workspace = generate(workspace([], actor: other_user))

      # Try to access it - should get redirect error
      assert {:error, {:redirect, %{to: "/preferences", flash: flash}}} =
               live(conn, ~p"/preferences/workspace/#{other_workspace.id}")

      # Should have error flash message
      assert flash["error"] == "You do not have access to this workspace"
    end

    test "redirects when workspace does not exist", %{conn: conn, user: _user} do
      # Try to access non-existent workspace
      fake_id = Ash.UUID.generate()

      # Try to access it - should get redirect error
      assert {:error, {:redirect, %{to: "/preferences", flash: flash}}} =
               live(conn, ~p"/preferences/workspace/#{fake_id}")

      # Should have error flash message
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
      Accounts.add_workspace_member!(member.id, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Should show both users' emails
      assert html =~ to_string(user.email)
      assert html =~ to_string(member.email)
    end

    test "displays pending invitations table", %{conn: conn, user: user, workspace: workspace} do
      email = "invited#{System.unique_integer([:positive])}@example.com"
      Accounts.create_invitation!(email, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Should show the invitation email
      assert html =~ email
    end
  end

  describe "remove-member event" do
    setup :register_and_log_in_user

    test "owner can remove a member", %{conn: conn, user: user, workspace: workspace} do
      member = generate(user())
      membership = Accounts.add_workspace_member!(member.id, workspace.id, actor: user)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Remove the member
      html =
        view
        |> element(~s|[phx-click="remove-member"][phx-value-id="#{membership.id}"]|)
        |> render_click()

      # Verify member email is no longer shown
      refute html =~ to_string(member.email)

      # Verify member was actually removed from database
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

      Accounts.add_workspace_member!(user.id, workspace.id, actor: owner)

      member2 = generate(user())
      Accounts.add_workspace_member!(member2.id, workspace.id, actor: owner)

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Member should not see remove buttons
      refute html =~ "Remove"

      # Verify no remove button elements exist
      refute has_element?(view, ~s|[phx-click="remove-member"]|)
    end
  end

  describe "revoke-invitation event" do
    setup :register_and_log_in_user

    test "owner can revoke an invitation", %{conn: conn, user: user, workspace: workspace} do
      email = "invited#{System.unique_integer([:positive])}@example.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Revoke the invitation
      html =
        view
        |> element(~s|[phx-click="revoke-invitation"][phx-value-id="#{invitation.id}"]|)
        |> render_click()

      # Verify invitation email is no longer shown
      refute html =~ email

      # Verify invitation was actually revoked from database
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

      Accounts.add_workspace_member!(user.id, workspace.id, actor: owner)

      email = "invited#{System.unique_integer([:positive])}@example.com"
      Accounts.create_invitation!(email, workspace.id, actor: owner)

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Member should see the invitation but not the revoke button
      assert html =~ email
      refute html =~ "Revoke"

      # Verify no revoke button elements exist
      refute has_element?(view, ~s|[phx-click="revoke-invitation"]|)
    end
  end

  describe "show-invite-modal event" do
    setup :register_and_log_in_user

    test "opens invite modal", %{conn: conn, user: _user, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Click invite button
      html =
        view
        |> element(~s|[phx-click="show-invite-modal"]|)
        |> render_click()

      # Modal should be visible
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

      # Open modal first
      view
      |> element(~s|[phx-click="show-invite-modal"]|)
      |> render_click()

      # Simulate invitation sent message
      send(view.pid, {:invitation_sent, nil})

      # Give it a moment to process
      :timer.sleep(50)

      # Modal should be hidden
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
      Accounts.add_workspace_member!(user.id, workspace.id, actor: owner)

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      # Member should see the integration card but not the connect button
      assert html =~ "Integrations"
      assert html =~ "GitHub"
      refute has_element?(view, ~s|[phx-click="show-github-modal"]|)
    end

    test "member sees badge instead of buttons when connected", %{conn: conn, user: user} do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))
      Accounts.add_workspace_member!(user.id, workspace.id, actor: owner)

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

      # Open confirmation modal
      view
      |> element(~s|[phx-click="show-disconnect-confirmation"]|)
      |> render_click()

      # Confirm disconnect
      html =
        view
        |> element(~s|[phx-click="confirm-disconnect-github"]|)
        |> render_click()

      assert html =~ "Not connected"
      assert html =~ "Connect"

      # Verify connection was actually deleted
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

      # Open confirmation modal
      view
      |> element(~s|[phx-click="show-disconnect-confirmation"]|)
      |> render_click()

      # Cancel using the Cancel button (not the X circle button)
      html =
        view
        |> element(~s|button.btn-ghost:not(.btn-circle)[phx-click="cancel-disconnect-github"]|)
        |> render_click()

      # Modal should be closed, still connected
      refute html =~ "Are you sure"
      assert html =~ "Connected"
    end
  end
end
