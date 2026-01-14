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

  describe "sub-task drag and drop" do
    setup :register_and_log_in_user

    setup %{user: user, workspace: workspace} do
      todo_state = create_task_state("Todo", 1)
      done_state = create_task_state("Done", 2, is_complete: true)

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id, title: "Parent Task"],
            actor: user,
            tenant: workspace.id
          )
        )

      sub_task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: todo_state.id,
              title: "Draggable Sub Task",
              parent_task_id: task.id
            ],
            actor: user,
            tenant: workspace.id
          )
        )

      %{task: task, sub_task: sub_task, todo_state: todo_state, done_state: done_state}
    end

    test "moves sub-task to new state via task-moved event", %{
      conn: conn,
      task: task,
      sub_task: sub_task,
      done_state: done_state,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      # Simulate the drag-and-drop by sending the task-moved event to the component
      view
      |> element("#sub-tasks-#{task.id}")
      |> render_hook("task-moved", %{
        "task_id" => sub_task.id,
        "new_state_id" => done_state.id
      })

      # Verify the sub-task state was updated in the database
      updated_sub_task =
        Tasks.get_task!(sub_task.id,
          actor: user,
          tenant: workspace.id,
          load: [:task_state]
        )

      assert updated_sub_task.task_state.id == done_state.id
    end

    test "preserves sub-task count after drag and drop", %{
      conn: conn,
      task: task,
      sub_task: sub_task,
      done_state: done_state
    } do
      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Sub-tasks (1)"
      assert html =~ sub_task.title

      # Simulate the drag-and-drop
      html =
        view
        |> element("#sub-tasks-#{task.id}")
        |> render_hook("task-moved", %{
          "task_id" => sub_task.id,
          "new_state_id" => done_state.id
        })

      # Sub-task count should still be 1
      assert html =~ "Sub-tasks (1)"
      assert html =~ sub_task.title
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

  describe "task dependencies" do
    setup :register_and_log_in_user

    setup %{user: user, workspace: workspace} do
      todo_state = create_task_state("Todo", 1)
      done_state = create_task_state("Done", 2, is_complete: true)

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id, title: "Main Task"],
            actor: user,
            tenant: workspace.id
          )
        )

      %{task: task, todo_state: todo_state, done_state: done_state}
    end

    test "displays dependencies section when task loads", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Blocked by"
    end

    test "displays 'Blocks' section for dependents", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Blocked by"
    end

    test "can add dependency by entering human_id", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      user: user,
      workspace: workspace
    } do
      dependency_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id, title: "Dependency Task"],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      html =
        view
        |> element("form[phx-submit=\"add-dependency\"]")
        |> render_submit(%{human_id: dependency_task.human_id})

      assert html =~ dependency_task.human_id
      assert html =~ "Dependency added"
    end

    test "shows error for invalid human_id", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      html =
        view
        |> element("form[phx-submit=\"add-dependency\"]")
        |> render_submit(%{human_id: "INVALID-123"})

      assert html =~ "Task with ID INVALID-123 not found"
    end

    test "shows error for circular dependency", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      user: user,
      workspace: workspace
    } do
      task_b =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      # Create A→B
      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: task_b.id},
        actor: user,
        tenant: workspace.id
      )

      # Try to create B→A (circular)
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task_b.human_id}")

      html =
        view
        |> element("form[phx-submit=\"add-dependency\"]")
        |> render_submit(%{human_id: task.human_id})

      assert html =~ "circular dependency"
    end

    test "can remove dependency", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      user: user,
      workspace: workspace
    } do
      dependency_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      task_dependency =
        Tasks.create_task_dependency!(
          %{task_id: task.id, depends_on_task_id: dependency_task.id},
          actor: user,
          tenant: workspace.id
        )

      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      html =
        view
        |> element(
          ~s|button[phx-click="remove-dependency"][phx-value-id="#{task_dependency.id}"]|
        )
        |> render_click()

      refute html =~ dependency_task.human_id
      assert html =~ "Dependency removed"
    end

    test "displays blocked badge when task has incomplete dependencies", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      user: user,
      workspace: workspace
    } do
      dependency_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: dependency_task.id},
        actor: user,
        tenant: workspace.id
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "badge badge-warning"
      assert html =~ ">Blocked</span>"
    end

    test "does not display blocked badge when dependencies are complete", %{
      conn: conn,
      task: task,
      done_state: done_state,
      user: user,
      workspace: workspace
    } do
      complete_dependency =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: done_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: complete_dependency.id},
        actor: user,
        tenant: workspace.id
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      refute html =~ "badge badge-warning"
    end

    test "shows completion warning when completing blocked task", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      done_state: done_state,
      user: user,
      workspace: workspace
    } do
      dependency_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: dependency_task.id},
        actor: user,
        tenant: workspace.id
      )

      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      html =
        view
        |> element("#task-state-#{task.id} button[phx-value-state-id=\"#{done_state.id}\"]")
        |> render_click()

      assert html =~ "Incomplete Dependencies"
      assert html =~ "This task depends on 1 incomplete task(s)"
      assert html =~ "Complete Anyway"
    end

    test "can complete task despite warning", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      done_state: done_state,
      user: user,
      workspace: workspace
    } do
      dependency_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: dependency_task.id},
        actor: user,
        tenant: workspace.id
      )

      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      # Trigger completion warning
      view
      |> element("#task-state-#{task.id} button[phx-value-state-id=\"#{done_state.id}\"]")
      |> render_click()

      # Confirm completion
      html =
        view
        |> element(
          "#task-state-#{task.id}-completion-warning button[phx-click=\"confirm-complete\"]"
        )
        |> render_click()

      # Verify task state was updated
      updated_task =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id,
          load: [:task_state]
        )

      assert updated_task.task_state.id == done_state.id
      refute html =~ "Incomplete Dependencies"
    end

    test "can cancel completion warning", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      done_state: done_state,
      user: user,
      workspace: workspace
    } do
      dependency_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: dependency_task.id},
        actor: user,
        tenant: workspace.id
      )

      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      # Trigger completion warning
      view
      |> element("#task-state-#{task.id} button[phx-value-state-id=\"#{done_state.id}\"]")
      |> render_click()

      # Cancel completion - target the "Cancel" button specifically by text
      html =
        view
        |> element("#task-state-#{task.id}-completion-warning button", "Cancel")
        |> render_click()

      # Verify task state was NOT updated
      updated_task =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id,
          load: [:task_state]
        )

      assert updated_task.task_state.id == todo_state.id
      refute html =~ "Incomplete Dependencies"
    end

    test "displays dependents (tasks that depend on this task)", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      user: user,
      workspace: workspace
    } do
      dependent_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      Tasks.create_task_dependency!(
        %{task_id: dependent_task.id, depends_on_task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Blocks"
      assert html =~ dependent_task.human_id
    end

    test "updates UI when dependency added via PubSub", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      dependency_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      # Add dependency in another process (simulating another user)
      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: dependency_task.id},
        actor: user,
        tenant: workspace.id
      )

      # Give PubSub time to propagate
      Process.sleep(100)

      html = render(view)
      assert html =~ dependency_task.human_id
    end

    test "updates UI when dependency removed via PubSub", %{
      conn: conn,
      task: task,
      todo_state: todo_state,
      user: user,
      workspace: workspace
    } do
      dependency_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: todo_state.id],
            actor: user,
            tenant: workspace.id
          )
        )

      task_dependency =
        Tasks.create_task_dependency!(
          %{task_id: task.id, depends_on_task_id: dependency_task.id},
          actor: user,
          tenant: workspace.id
        )

      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")
      assert html =~ dependency_task.human_id

      # Remove dependency in another process
      Tasks.destroy_task_dependency!(task_dependency.id, actor: user, tenant: workspace.id)

      # Give PubSub time to propagate
      Process.sleep(100)

      html = render(view)
      refute html =~ dependency_task.human_id
    end

    test "does not submit add-dependency form with empty human_id", %{
      conn: conn,
      task: task,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      # Try to submit with empty human_id
      view
      |> element("form[phx-submit=\"add-dependency\"]")
      |> render_submit(%{human_id: ""})

      # Verify no dependency was created
      task_with_deps =
        Tasks.get_task_by_human_id!(task.human_id,
          actor: user,
          tenant: workspace.id,
          load: [:dependencies]
        )

      assert Enum.empty?(task_with_deps.dependencies)
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
