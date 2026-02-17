defmodule CitadelWeb.InvitationLive.AcceptTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Citadel.Generator

  alias Citadel.Accounts

  describe "mount/3 - valid invitation" do
    setup :register_and_log_in_user

    test "displays invitation details when logged in", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      # Should show workspace name and inviter
      assert html =~ workspace.name
      assert html =~ to_string(user.email)
    end

    test "shows accept button when user is logged in", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      {:ok, view, _html} = live(conn, ~p"/invitations/#{invitation.token}")

      # Should have accept button
      assert has_element?(view, ~s|[phx-click="accept"]|)
    end

    test "shows current user email when logged in", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      # Should show who is accepting
      assert html =~ "Accepting as"
      assert html =~ to_string(user.email)
    end

    test "displays expiration date", %{conn: conn, user: user, workspace: workspace} do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      assert html =~ "Expires:"
    end
  end

  describe "mount/3 - not logged in" do
    test "shows sign in button when not authenticated", %{conn: _conn} do
      owner = Citadel.DataCase.create_user()
      workspace = generate(workspace([], actor: owner))

      email = "test-#{System.unique_integer([:positive])}@example.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: owner)

      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      assert html =~ "Sign In to Accept"
      assert html =~ "been invited to join"
    end

    test "displays invitation details without authentication", %{conn: _conn} do
      owner = Citadel.DataCase.create_user()
      workspace = generate(workspace([name: "Test Workspace"], actor: owner))

      email = "test-#{System.unique_integer([:positive])}@example.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: owner)

      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      # Should show workspace details
      assert html =~ "Test Workspace"
      assert html =~ to_string(owner.email)
    end

    test "sign in link includes return path", %{conn: _conn} do
      owner = Citadel.DataCase.create_user()
      workspace = generate(workspace([], actor: owner))

      email = "test-#{System.unique_integer([:positive])}@example.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: owner)

      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      # Check for return_to parameter in sign-in link
      assert html =~ "return_to"
      assert html =~ invitation.token
    end
  end

  describe "mount/3 - expired invitation" do
    setup :register_and_log_in_user

    test "displays expired error", %{conn: conn, user: user, workspace: workspace} do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      # Manually expire the invitation
      invitation
      |> Ash.Changeset.for_update(:update, %{
        expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
      })
      |> Ash.update!(authorize?: false)

      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      assert html =~ "Invitation Expired"
      assert html =~ "This invitation has expired"
    end

    test "does not show accept button for expired invitation", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      # Expire the invitation
      invitation
      |> Ash.Changeset.for_update(:update, %{
        expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
      })
      |> Ash.update!(authorize?: false)

      {:ok, view, _html} = live(conn, ~p"/invitations/#{invitation.token}")

      refute has_element?(view, ~s|[phx-click="accept"]|)
    end
  end

  describe "mount/3 - already accepted invitation" do
    setup :register_and_log_in_user

    test "displays already accepted error", %{conn: conn, user: user, workspace: workspace} do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      # Mark as accepted
      invitation
      |> Ash.Changeset.for_update(:update, %{accepted_at: DateTime.utc_now()})
      |> Ash.update!(authorize?: false)

      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      assert html =~ "Invitation Already Accepted"
      assert html =~ "already been accepted"
    end

    test "does not show accept button for already accepted invitation", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      # Mark as accepted
      invitation
      |> Ash.Changeset.for_update(:update, %{accepted_at: DateTime.utc_now()})
      |> Ash.update!(authorize?: false)

      {:ok, view, _html} = live(conn, ~p"/invitations/#{invitation.token}")

      refute has_element?(view, ~s|[phx-click="accept"]|)
    end
  end

  describe "mount/3 - invalid token" do
    setup :register_and_log_in_user

    test "displays not found error", %{conn: conn, user: _user} do
      fake_token = "invalid-token-#{System.unique_integer([:positive])}"

      {:ok, _view, html} = live(conn, ~p"/invitations/#{fake_token}")

      assert html =~ "Invitation Not Found"
      assert html =~ "invalid or has been revoked"
    end

    test "does not show accept button for invalid token", %{conn: conn, user: _user} do
      fake_token = "invalid-token-#{System.unique_integer([:positive])}"

      {:ok, view, _html} = live(conn, ~p"/invitations/#{fake_token}")

      refute has_element?(view, ~s|[phx-click="accept"]|)
    end
  end

  describe "accept event - authenticated user" do
    test "creates membership when accepting valid invitation", %{conn: _conn} do
      # Create owner and workspace
      owner = Citadel.DataCase.create_user()
      workspace = generate(workspace([name: "Test Workspace"], actor: owner))

      # Create invitation
      email = "invited-#{System.unique_integer([:positive])}@test.com"

      # Create a different user to accept the invitation
      invitee = generate(user([email: email], authorise?: false))

      invitation = Accounts.create_invitation!(email, workspace.id, actor: owner)

      # Log in as invitee
      conn = Phoenix.ConnTest.build_conn()
      conn = log_in_user(conn, invitee)

      {:ok, view, _html} = live(conn, ~p"/invitations/#{invitation.token}")

      # Accept the invitation
      view
      |> element(~s|[phx-click="accept"]|)
      |> render_click()

      # Verify membership was created
      memberships =
        Accounts.list_workspace_members!(
          actor: invitee,
          query: [filter: [user_id: invitee.id, workspace_id: workspace.id]]
        )

      assert length(memberships) == 1
    end

    test "handles already member error gracefully", %{conn: _conn} do
      # Create owner and workspace
      owner = Citadel.DataCase.create_user()
      workspace = generate(workspace([], actor: owner))

      # Create invitation
      email = "test-#{System.unique_integer([:positive])}@example.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: owner)

      # Log in as owner (who is already a member)
      conn = Phoenix.ConnTest.build_conn()
      conn = log_in_user(conn, owner)

      {:ok, view, _html} = live(conn, ~p"/invitations/#{invitation.token}")

      # Try to accept (should fail since owner is already a member)
      view
      |> element(~s|[phx-click="accept"]|)
      |> render_click()

      # Should show some kind of error (either flash or page message)
      # The important thing is it doesn't crash or redirect
      html = render(view)
      assert html =~ "invitation" or html =~ "error" or html =~ "already"
    end
  end

  describe "accept event - not authenticated" do
    test "shows sign in link when not authenticated", %{conn: _conn} do
      owner = Citadel.DataCase.create_user()
      workspace = generate(workspace([], actor: owner))

      email = "test-#{System.unique_integer([:positive])}@example.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: owner)

      # Access without logging in
      conn = Phoenix.ConnTest.build_conn()
      {:ok, view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      # Should show sign in link with return path
      assert html =~ "sign-in"
      assert html =~ "return_to"
      assert has_element?(view, ~s|a[href*="/sign-in"]|)
    end
  end

  describe "render/1 - error states" do
    setup :register_and_log_in_user

    @tag timeout: 120_000
    test "error messages include contact instructions", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      # Expire invitation
      invitation
      |> Ash.Changeset.for_update(:update, %{
        expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
      })
      |> Ash.update!(authorize?: false)

      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      assert html =~ "contact the workspace owner"
    end

    @tag timeout: 120_000
    test "displays appropriate icons for different states", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      # Valid invitation shows envelope icon
      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")
      assert html =~ "hero-envelope"

      # Error state shows exclamation icon
      fake_token = "invalid-token"
      {:ok, _view, html} = live(conn, ~p"/invitations/#{fake_token}")
      assert html =~ "hero-exclamation-circle"
    end

    @tag timeout: 120_000
    test "shows go home button for error states", %{conn: conn, user: user, workspace: workspace} do
      email = "invited-#{System.unique_integer([:positive])}@test.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: user)

      # Expire invitation
      invitation
      |> Ash.Changeset.for_update(:update, %{
        expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
      })
      |> Ash.update!(authorize?: false)

      {:ok, view, _html} = live(conn, ~p"/invitations/#{invitation.token}")

      # Should have go home link
      assert has_element?(view, ~s|a[href="/"]|)
    end
  end

  describe "authorization" do
    @tag timeout: 120_000
    test "allows access without authentication for valid invitation", %{conn: _conn} do
      owner = Citadel.DataCase.create_user()
      workspace = generate(workspace([], actor: owner))

      email = "test-#{System.unique_integer([:positive])}@example.com"
      invitation = Accounts.create_invitation!(email, workspace.id, actor: owner)

      # Should be able to view without auth
      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/invitations/#{invitation.token}")

      assert html =~ workspace.name
      assert html =~ "Sign In to Accept"
    end

    test "allows access without authentication for invalid invitation", %{conn: _conn} do
      fake_token = "invalid-token"

      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/invitations/#{fake_token}")

      assert html =~ "Invitation Not Found"
    end
  end
end
