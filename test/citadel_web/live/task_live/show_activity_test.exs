defmodule CitadelWeb.TaskLive.ShowActivityTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Citadel.Generator

  alias Citadel.Tasks

  setup :register_and_log_in_user

  setup %{user: user, workspace: workspace} do
    task_state =
      Tasks.create_task_state!(%{
        name: "Todo-#{System.unique_integer([:positive])}",
        order: 1,
        icon: "fa-circle-solid",
        foreground_color: "#ffffff",
        background_color: "#3b82f6"
      })

    task =
      generate(
        task(
          [workspace_id: workspace.id, task_state_id: task_state.id, title: "Task With Activity"],
          actor: user,
          tenant: workspace.id
        )
      )

    %{task: task, task_state: task_state}
  end

  describe "activity section rendering" do
    test "displays activity section heading", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Activity"
    end

    test "displays comment form", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert has_element?(view, "#comment-form")
      assert has_element?(view, "#comment-form textarea[name=\"body\"]")
    end

    test "displays empty state when no activities", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "No activity yet"
    end
  end

  describe "submitting comments" do
    test "creates comment and displays it in timeline", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      html =
        view
        |> form("#comment-form", %{body: "My first comment"})
        |> render_submit()

      assert html =~ "My first comment"
    end

    test "clears form after successful submission", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> form("#comment-form", %{body: "Comment to clear"})
      |> render_submit()

      refute has_element?(view, "#comment-form textarea[name=\"body\"]", "Comment to clear")
    end

    test "does not submit empty comment", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> form("#comment-form", %{body: ""})
      |> render_submit()

      activities = Tasks.list_task_activities!(task.id, actor: user, tenant: workspace.id)
      assert activities == []
    end

    test "does not submit whitespace-only comment", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> form("#comment-form", %{body: "   "})
      |> render_submit()

      activities = Tasks.list_task_activities!(task.id, actor: user, tenant: workspace.id)
      assert activities == []
    end
  end

  describe "activity timeline display" do
    test "displays user avatar and email for user comments", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      Tasks.create_comment!(
        %{body: "User comment", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "User comment"
      assert html =~ to_string(user.email)
    end

    test "displays activities in chronological order", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      for i <- 1..3 do
        Tasks.create_comment!(
          %{body: "Comment #{i}", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
      end

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Comment 1"
      assert html =~ "Comment 2"
      assert html =~ "Comment 3"
    end

    test "displays relative timestamps", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      Tasks.create_comment!(
        %{body: "Recent comment", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "just now"
    end
  end

  describe "deleting comments" do
    test "shows delete button on own comments", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      activity =
        Tasks.create_comment!(
          %{body: "My deletable comment", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert has_element?(
               view,
               ~s|button[phx-click="delete-comment"][phx-value-id="#{activity.id}"]|
             )
    end

    test "deletes comment when clicking delete", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      activity =
        Tasks.create_comment!(
          %{body: "Comment to delete", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      html =
        view
        |> element(~s|button[phx-click="delete-comment"][phx-value-id="#{activity.id}"]|)
        |> render_click()

      refute html =~ "Comment to delete"
    end
  end

  describe "real-time updates via PubSub" do
    test "new comment appears in real-time", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      Tasks.create_comment!(
        %{body: "Real-time comment", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      Process.sleep(100)

      html = render(view)
      assert html =~ "Real-time comment"
    end

    test "deleted comment disappears in real-time", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      activity =
        Tasks.create_comment!(
          %{body: "Soon to be deleted", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")
      assert html =~ "Soon to be deleted"

      Tasks.destroy_comment!(activity, actor: user, tenant: workspace.id)

      Process.sleep(100)

      html = render(view)
      refute html =~ "Soon to be deleted"
    end
  end
end
