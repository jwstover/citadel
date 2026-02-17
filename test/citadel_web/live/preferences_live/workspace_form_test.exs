defmodule CitadelWeb.PreferencesLive.WorkspaceFormTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Citadel.Generator

  alias Citadel.Accounts

  describe "mount/3 - new workspace" do
    setup :register_and_log_in_user

    test "loads new workspace form", %{conn: conn, user: _user} do
      {:ok, _view, html} = live(conn, ~p"/preferences/workspaces/new")

      assert html =~ "New Workspace"
      assert html =~ "Workspace Name"
      assert html =~ "Create Workspace"
    end

    test "form starts empty", %{conn: conn, user: _user} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/new")

      assert view
             |> element("form")
             |> render() =~ ~s(name="form[name]")
    end
  end

  describe "mount/3 - edit workspace" do
    setup :register_and_log_in_user

    test "loads edit workspace form for owner", %{conn: conn, user: _user, workspace: workspace} do
      {:ok, _view, html} = live(conn, ~p"/preferences/workspaces/#{workspace.id}/edit")

      assert html =~ "Edit Workspace"
      assert html =~ "Workspace Name"
      assert html =~ "Update Workspace"
      assert html =~ workspace.name
    end

    test "redirects non-owner trying to edit", %{conn: conn, user: user} do
      other_user = generate(user())
      other_workspace = generate(workspace([name: "Others Workspace"], actor: other_user))

      add_user_to_workspace(user.id, other_workspace.id, actor: other_user)

      assert {:error, {:redirect, %{to: "/preferences", flash: flash}}} =
               live(conn, ~p"/preferences/workspaces/#{other_workspace.id}/edit")

      assert flash["error"] == "You do not have permission to edit this workspace"
    end

    test "redirects when workspace does not exist", %{conn: conn, user: _user} do
      fake_id = Ash.UUID.generate()

      assert {:error, {:redirect, %{to: "/preferences", flash: flash}}} =
               live(conn, ~p"/preferences/workspaces/#{fake_id}/edit")

      assert flash["error"] == "You do not have permission to edit this workspace"
    end

    test "redirects when user is not member of workspace", %{conn: conn, user: _user} do
      other_user = generate(user())
      other_workspace = generate(workspace([name: "Others Workspace"], actor: other_user))

      assert {:error, {:redirect, %{to: "/preferences", flash: flash}}} =
               live(conn, ~p"/preferences/workspaces/#{other_workspace.id}/edit")

      assert flash["error"] == "You do not have permission to edit this workspace"
    end
  end

  describe "save event - create" do
    setup :register_and_log_in_user

    test "creates new workspace with valid data", %{conn: conn, user: user, workspace: workspace} do
      # Upgrade to pro to allow multiple workspaces
      org = Citadel.Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)
      upgrade_to_pro(org)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/new")

      workspace_name = "My Team Workspace #{System.unique_integer([:positive])}"

      view
      |> form("form", form: %{name: workspace_name})
      |> render_submit()

      workspaces =
        Accounts.list_workspaces!(
          actor: user,
          query: [filter: [name: workspace_name]]
        )

      assert length(workspaces) == 1
      created_workspace = hd(workspaces)
      assert created_workspace.name == workspace_name

      assert_redirected(view, "/preferences/workspace/#{created_workspace.id}")
    end

    test "shows error with empty name", %{conn: conn, user: _user} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/new")

      html =
        view
        |> form("form", form: %{name: ""})
        |> render_submit()

      assert html =~ "New Workspace"
      refute has_element?(view, ".alert-success")
    end

    test "shows error with name too long", %{conn: conn, user: _user} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/new")

      long_name = String.duplicate("a", 101)

      html =
        view
        |> form("form", form: %{name: long_name})
        |> render_submit()

      assert html =~ "New Workspace"
    end

    test "redirects to workspace details after creation", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      # Upgrade to pro to allow multiple workspaces
      org = Citadel.Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)
      upgrade_to_pro(org)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/new")

      workspace_name = "New Team #{System.unique_integer([:positive])}"

      view
      |> form("form", form: %{name: workspace_name})
      |> render_submit()

      workspaces =
        Accounts.list_workspaces!(
          actor: user,
          query: [filter: [name: workspace_name]]
        )

      created_workspace = hd(workspaces)

      flash = assert_redirected(view, "/preferences/workspace/#{created_workspace.id}")
      assert flash["info"] == "Workspace created successfully"
    end
  end

  describe "save event - update" do
    setup :register_and_log_in_user

    test "updates workspace name with valid data", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/#{workspace.id}/edit")

      new_name = "Updated Name #{System.unique_integer([:positive])}"

      view
      |> form("form", form: %{name: new_name})
      |> render_submit()

      updated_workspace = Accounts.get_workspace_by_id!(workspace.id, actor: user)
      assert updated_workspace.name == new_name

      assert_redirected(view, "/preferences/workspace/#{workspace.id}")
    end

    test "shows error with invalid data", %{conn: conn, user: _user, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/#{workspace.id}/edit")

      html =
        view
        |> form("form", form: %{name: ""})
        |> render_submit()

      assert html =~ "Edit Workspace"
    end

    test "redirects to workspace details after update with success message", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/#{workspace.id}/edit")

      new_name = "Updated #{System.unique_integer([:positive])}"

      view
      |> form("form", form: %{name: new_name})
      |> render_submit()

      updated_workspace = Accounts.get_workspace_by_id!(workspace.id, actor: user)

      flash = assert_redirected(view, "/preferences/workspace/#{updated_workspace.id}")
      assert flash["info"] == "Workspace updated successfully"
    end
  end

  describe "cancel event" do
    setup :register_and_log_in_user

    test "redirects to preferences when creating new workspace", %{conn: conn, user: _user} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/new")

      view
      |> element(~s|[phx-click="cancel"]|)
      |> render_click()

      assert_redirected(view, "/preferences")
    end

    test "redirects to workspace details when editing", %{
      conn: conn,
      user: _user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/#{workspace.id}/edit")

      view
      |> element(~s|[phx-click="cancel"]|)
      |> render_click()

      assert_redirected(view, "/preferences/workspace/#{workspace.id}")
    end
  end

  describe "authentication" do
    test "redirects to login when not authenticated for new workspace", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn()

      {:error, {:redirect, %{to: redirect_path}}} =
        live(conn, ~p"/preferences/workspaces/new")

      assert redirect_path =~ "/sign-in"
    end

    test "redirects to login when not authenticated for edit", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn()
      fake_id = Ash.UUID.generate()

      {:error, {:redirect, %{to: redirect_path}}} =
        live(conn, ~p"/preferences/workspaces/#{fake_id}/edit")

      assert redirect_path =~ "/sign-in"
    end
  end

  describe "render/1" do
    setup :register_and_log_in_user

    test "displays workspace name input field", %{conn: conn, user: _user} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/new")

      assert has_element?(view, "input[name='form[name]']")
    end

    test "displays placeholder text in name field", %{conn: conn, user: _user} do
      {:ok, _view, html} = live(conn, ~p"/preferences/workspaces/new")

      assert html =~ "My Team, Personal, Work Projects"
    end

    test "displays cancel and submit buttons", %{conn: conn, user: _user} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspaces/new")

      assert has_element?(view, ~s|button[type="button"][phx-click="cancel"]|)
      assert has_element?(view, ~s|button[type="submit"]|)
    end

    test "submit button text changes based on action", %{
      conn: conn,
      user: _user,
      workspace: workspace
    } do
      {:ok, _view, html} = live(conn, ~p"/preferences/workspaces/new")
      assert html =~ "Create Workspace"

      {:ok, _view, html} = live(conn, ~p"/preferences/workspaces/#{workspace.id}/edit")
      assert html =~ "Update Workspace"
    end
  end
end
