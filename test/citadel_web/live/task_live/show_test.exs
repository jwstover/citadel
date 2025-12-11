defmodule CitadelWeb.TaskLive.ShowTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Citadel.Generator

  alias Citadel.Tasks

  describe "mount/3" do
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

    test "displays task title", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Test Task"
    end

    test "displays task human_id in breadcrumbs", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ task.human_id
    end

    test "displays priority badge", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "medium"
    end
  end

  describe "inline title editing" do
    setup :register_and_log_in_user

    setup %{user: user, workspace: workspace} do
      task_state = create_task_state("Todo", 1)

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id, title: "Original Title"],
            actor: user,
            tenant: workspace.id
          )
        )

      sub_task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: task_state.id,
              title: "Sub Task",
              parent_task_id: task.id
            ],
            actor: user,
            tenant: workspace.id
          )
        )

      %{task: task, task_state: task_state, sub_task: sub_task}
    end

    test "saves title on blur", %{conn: conn, task: task, user: user, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> element("input[name=\"title\"]")
      |> render_blur(%{value: "Updated Title"})

      updated_task =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert updated_task.title == "Updated Title"
    end

    test "saves title on Enter key", %{conn: conn, task: task, user: user, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> element("input[name=\"title\"]")
      |> render_keydown(%{key: "Enter", value: "Title via Enter"})

      updated_task =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert updated_task.title == "Title via Enter"
    end

    test "does not save empty title", %{conn: conn, task: task, user: user, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> element("input[name=\"title\"]")
      |> render_blur(%{value: "   "})

      updated_task =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert updated_task.title == "Original Title"
    end

    test "does not save unchanged title", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> element("input[name=\"title\"]")
      |> render_blur(%{value: "Original Title"})

      updated_task =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert updated_task.title == "Original Title"
    end

    test "preserves sub-tasks after title update", %{conn: conn, task: task, sub_task: sub_task} do
      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ sub_task.title

      html =
        view
        |> element("input[name=\"title\"]")
        |> render_blur(%{value: "New Title"})

      assert html =~ sub_task.title
      assert html =~ "Sub-tasks (1)"
    end
  end

  describe "inline due date editing" do
    setup :register_and_log_in_user

    setup %{user: user, workspace: workspace} do
      task_state = create_task_state("Todo", 1)

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      %{task: task, task_state: task_state}
    end

    test "saves due date on blur", %{conn: conn, task: task, user: user, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> element("input[name=\"due_date\"]")
      |> render_blur(%{value: "2025-12-25"})

      updated_task =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert updated_task.due_date == ~D[2025-12-25]
    end

    test "clears due date when empty", %{conn: conn, user: user, workspace: workspace} do
      task_state = create_task_state("Todo With Date", 2)

      task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: task_state.id,
              due_date: ~D[2025-01-15]
            ],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> element("input[name=\"due_date\"]")
      |> render_blur(%{value: ""})

      updated_task =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert is_nil(updated_task.due_date)
    end

    test "preserves sub-tasks after due date update", %{
      conn: conn,
      task: task,
      task_state: task_state,
      user: user,
      workspace: workspace
    } do
      sub_task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: task_state.id,
              title: "Sub Task for Due Date",
              parent_task_id: task.id
            ],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ sub_task.title

      html =
        view
        |> element("input[name=\"due_date\"]")
        |> render_blur(%{value: "2025-12-25"})

      assert html =~ sub_task.title
      assert html =~ "Sub-tasks (1)"
    end
  end

  describe "priority dropdown" do
    setup :register_and_log_in_user

    setup %{user: user, workspace: workspace} do
      task_state = create_task_state("Todo", 1)

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id, priority: :low],
            actor: user,
            tenant: workspace.id
          )
        )

      %{task: task, task_state: task_state}
    end

    test "displays current priority", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "low"
    end

    test "changes priority when selecting from dropdown", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> element("#task-priority-#{task.id} button[phx-value-priority=\"high\"]")
      |> render_click()

      updated_task =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert updated_task.priority == :high
    end

    test "updates UI after priority change", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      html =
        view
        |> element("#task-priority-#{task.id} button[phx-value-priority=\"urgent\"]")
        |> render_click()

      assert html =~ "urgent"
    end

    test "preserves sub-tasks after priority change", %{
      conn: conn,
      task: task,
      task_state: task_state,
      user: user,
      workspace: workspace
    } do
      sub_task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: task_state.id,
              title: "Sub Task for Priority",
              parent_task_id: task.id
            ],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ sub_task.title

      html =
        view
        |> element("#task-priority-#{task.id} button[phx-value-priority=\"urgent\"]")
        |> render_click()

      assert html =~ sub_task.title
      assert html =~ "Sub-tasks (1)"
    end
  end

  describe "assignee selection" do
    setup :register_and_log_in_user

    setup %{user: user, workspace: workspace} do
      task_state = create_task_state("Todo", 1)

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      %{task: task, task_state: task_state}
    end

    test "displays assignee select component", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert has_element?(view, "#task-assignees-#{task.id}")
    end

    test "shows 'None' when no assignees", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "None"
    end

    test "can toggle assignee dropdown", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> element("#task-assignees-#{task.id} > div[phx-click=\"toggle\"]")
      |> render_click()

      assert has_element?(
               view,
               "#task-assignees-#{task.id} input[placeholder=\"Search members...\"]"
             )
    end

    test "toggles member selection in UI", %{conn: conn, task: task, user: user} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> element("#task-assignees-#{task.id} > div[phx-click=\"toggle\"]")
      |> render_click()

      html =
        view
        |> element("#task-assignees-#{task.id} button[phx-value-id=\"#{user.id}\"]")
        |> render_click()

      assert html =~ "checked"
    end

    test "preserves sub-tasks after assignee change", %{
      conn: conn,
      task: task,
      task_state: task_state,
      user: user,
      workspace: workspace
    } do
      sub_task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: task_state.id,
              title: "Sub Task for Assignee",
              parent_task_id: task.id
            ],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ sub_task.title

      # Open dropdown and select user
      view
      |> element("#task-assignees-#{task.id} > div[phx-click=\"toggle\"]")
      |> render_click()

      html =
        view
        |> element("#task-assignees-#{task.id} button[phx-value-id=\"#{user.id}\"]")
        |> render_click()

      assert html =~ sub_task.title
      assert html =~ "Sub-tasks (1)"
    end
  end

  describe "task state dropdown" do
    setup :register_and_log_in_user

    setup %{user: user, workspace: workspace} do
      todo_state = create_task_state("Todo", 1)
      done_state = create_task_state("Done", 2, is_complete: true)

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      %{task: task, todo_state: todo_state, done_state: done_state}
    end

    test "displays task state dropdown", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert has_element?(view, "#task-state-#{task.id}")
    end

    test "changes task state when selecting from dropdown", %{
      conn: conn,
      task: task,
      done_state: done_state,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      view
      |> element("#task-state-#{task.id} button[phx-value-state-id=\"#{done_state.id}\"]")
      |> render_click()

      updated_task =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id,
          load: [:task_state]
        )

      assert updated_task.task_state.id == done_state.id
    end

    test "preserves sub-tasks after task state change", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      done_state: done_state,
      user: user,
      workspace: workspace
    } do
      sub_task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: todo_state.id,
              title: "Sub Task for State",
              parent_task_id: task.id
            ],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ sub_task.title

      html =
        view
        |> element("#task-state-#{task.id} button[phx-value-state-id=\"#{done_state.id}\"]")
        |> render_click()

      assert html =~ sub_task.title
      assert html =~ "Sub-tasks (1)"
    end
  end

  describe "read-only mode for non-editors" do
    setup :register_and_log_in_user

    setup %{workspace: _workspace} do
      owner = generate(user())
      owner_workspace = generate(workspace([], actor: owner))
      task_state = create_task_state("Todo", 1)

      task =
        generate(
          task(
            [workspace_id: owner_workspace.id, task_state_id: task_state.id, title: "Owner Task"],
            actor: owner,
            tenant: owner_workspace.id
          )
        )

      %{task: task, task_state: task_state, owner: owner, owner_workspace: owner_workspace}
    end

    test "non-member cannot access task", %{conn: conn, task: task} do
      assert_raise Ash.Error.Invalid, fn ->
        live(conn, ~p"/tasks/#{task.human_id}")
      end
    end
  end

  defp create_task_state(name, order, opts \\ []) do
    is_complete = Keyword.get(opts, :is_complete, false)

    Tasks.create_task_state!(%{
      name: name <> "-#{System.unique_integer([:positive])}",
      order: order,
      is_complete: is_complete,
      icon: "fa-circle-solid",
      foreground_color: "#ffffff",
      background_color: "#3b82f6"
    })
  end
end
