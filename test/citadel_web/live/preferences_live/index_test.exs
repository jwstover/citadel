defmodule CitadelWeb.PreferencesLive.IndexTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Citadel.Generator

  describe "mount/3" do
    setup :register_and_log_in_user

    test "loads user's workspaces", %{conn: conn, user: _user, workspace: workspace} do
      {:ok, _view, html} = live(conn, ~p"/preferences")

      assert html =~ workspace.name
    end

    test "loads multiple workspaces where user is owner or member", %{conn: conn, user: user} do
      generate(workspace([name: "Second Workspace"], actor: user))

      other_user = generate(user())
      workspace3 = generate(workspace([name: "Third Workspace"], actor: other_user))
      add_user_to_workspace(user.id, workspace3.id, actor: other_user)

      {:ok, _view, html} = live(conn, ~p"/preferences")

      assert html =~ "Second Workspace"
      assert html =~ "Third Workspace"
    end

    test "loads workspace owners to determine role", %{
      conn: conn,
      user: _user,
      workspace: workspace
    } do
      {:ok, _view, html} = live(conn, ~p"/preferences")

      assert html =~ workspace.name
      assert html =~ "Owner"
    end
  end

  describe "render/1" do
    setup :register_and_log_in_user

    test "displays Preferences heading", %{conn: conn, user: _user} do
      {:ok, _view, html} = live(conn, ~p"/preferences")

      assert html =~ "Preferences"
    end

    test "displays Workspaces section", %{conn: conn, user: _user} do
      {:ok, _view, html} = live(conn, ~p"/preferences")

      assert html =~ "Workspaces"
    end

    test "displays workspace names in table", %{conn: conn, user: user, workspace: workspace} do
      _workspace2 = generate(workspace([name: "Test Workspace"], actor: user))

      {:ok, _view, html} = live(conn, ~p"/preferences")

      assert html =~ workspace.name
      assert html =~ "Test Workspace"
    end

    test "displays 'Owner' role for workspaces owned by current user", %{
      conn: conn,
      user: _user,
      workspace: workspace
    } do
      {:ok, _view, html} = live(conn, ~p"/preferences")

      assert html =~ workspace.name
      assert html =~ "Owner"
    end

    test "displays 'Member' role for workspaces where user is a member" do
      user = Citadel.DataCase.create_user()

      other_user = generate(user())
      other_workspace = generate(workspace([name: "Others Workspace"], actor: other_user))

      add_user_to_workspace(user.id, other_workspace.id, actor: other_user)

      conn = Phoenix.ConnTest.build_conn()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/preferences")

      assert html =~ "Others Workspace"
      assert html =~ "Member"
    end

    test "displays both Owner and Member workspaces correctly", %{
      conn: conn,
      user: user,
      workspace: owned_workspace
    } do
      other_user = generate(user())
      member_workspace = generate(workspace([name: "Member Workspace"], actor: other_user))
      add_user_to_workspace(user.id, member_workspace.id, actor: other_user)

      {:ok, _view, html} = live(conn, ~p"/preferences")

      assert html =~ owned_workspace.name
      assert html =~ "Member Workspace"

      assert html =~ "Owner"
      assert html =~ "Member"
    end
  end

  describe "row navigation" do
    setup :register_and_log_in_user

    test "workspace preferences page is accessible", %{
      conn: conn,
      user: _user,
      workspace: workspace
    } do
      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ "Workspace:"
      assert html =~ "Members"
    end

    test "workspace rows exist in table", %{
      conn: conn,
      user: _user,
      workspace: _workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/preferences")

      assert has_element?(view, "#workspaces")
    end
  end

  describe "authentication" do
    test "redirects to login when not authenticated", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn()

      {:error, {:redirect, %{to: redirect_path}}} = live(conn, ~p"/preferences")

      assert redirect_path =~ "/sign-in"
    end

    test "requires authenticated user to access preferences", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn()

      assert {:error, {:redirect, _}} = live(conn, ~p"/preferences")
    end
  end
end
