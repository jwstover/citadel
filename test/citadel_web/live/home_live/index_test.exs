defmodule CitadelWeb.HomeLive.IndexTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Citadel.Generator

  alias Citadel.Tasks

  describe "mount/3" do
    setup :register_and_log_in_user

    test "renders the home page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "tasks-container"
    end

    test "does not show task form by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      refute html =~ "new-task-modal"
    end

    test "displays tasks list component", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "tasks-container"
    end
  end

  describe "new task button" do
    setup :register_and_log_in_user

    test "clicking new task shows the task form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = view |> element("button[phx-click='new-task']") |> render_click()

      assert html =~ "new-task-modal"
    end
  end

  describe "handle_event new-task" do
    setup :register_and_log_in_user

    test "shows task form when new-task event is triggered", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute render(view) =~ "new-task-modal"

      html = render_click(view, "new-task", %{})

      assert html =~ "new-task-modal"
    end
  end

  describe "handle_event close-new-task-form" do
    setup :register_and_log_in_user

    test "hides task form when close event is triggered", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open the form first
      render_click(view, "new-task", %{})
      assert render(view) =~ "new-task-modal"

      # Close the form
      html = render_click(view, "close-new-task-form", %{})

      refute html =~ "new-task-modal"
    end
  end

  describe "handle_info task_created" do
    setup :register_and_log_in_user

    setup %{user: user, workspace: workspace} do
      task_state = create_task_state("Todo", 1)

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id, title: "Test Task"],
            actor: user,
            tenant: workspace.id
          )
        )

      %{task: task, task_state: task_state}
    end

    test "closes task form after task is created", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open the form first
      render_click(view, "new-task", %{})
      assert render(view) =~ "new-task-modal"

      # Simulate task_created message
      send(view.pid, {:task_created, task})

      # Form should be closed
      refute render(view) =~ "new-task-modal"
    end
  end

  describe "handle_info task_state_changed" do
    setup :register_and_log_in_user

    setup %{user: user, workspace: workspace} do
      task_state = create_task_state("Todo", 1)

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id, title: "Test Task"],
            actor: user,
            tenant: workspace.id
          )
        )

      %{task: task, task_state: task_state}
    end

    test "handles task state change without error", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Simulate task_state_changed message - should not crash
      send(view.pid, {:task_state_changed, task})

      # View should still be alive and rendering
      assert render(view) =~ "tasks-container"
    end
  end

  describe "handle_info task_priority_changed" do
    setup :register_and_log_in_user

    setup %{user: user, workspace: workspace} do
      task_state = create_task_state("Todo", 1)

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id, title: "Test Task"],
            actor: user,
            tenant: workspace.id
          )
        )

      %{task: task, task_state: task_state}
    end

    test "handles task priority change without error", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Simulate task_priority_changed message - should not crash
      send(view.pid, {:task_priority_changed, task})

      # View should still be alive and rendering
      assert render(view) =~ "tasks-container"
    end
  end

  describe "authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/")
    end
  end

  defp create_task_state(name, order, opts \\ []) do
    is_complete = Keyword.get(opts, :is_complete, false)

    Tasks.create_task_state!(%{
      name: name <> "-#{System.unique_integer([:positive])}",
      order: order,
      is_complete: is_complete
    })
  end
end
