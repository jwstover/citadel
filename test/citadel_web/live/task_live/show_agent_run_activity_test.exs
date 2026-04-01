defmodule CitadelWeb.TaskLive.ShowAgentRunActivityTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Citadel.Tasks

  setup :register_and_log_in_user

  setup %{user: user, workspace: workspace} do
    task_state =
      Tasks.create_task_state!(%{
        name: "In Progress #{System.unique_integer([:positive])}",
        order: 1
      })

    task =
      Tasks.create_task!(
        %{
          title: "Agent Run Activity Test #{System.unique_integer([:positive])}",
          task_state_id: task_state.id
        },
        actor: user,
        tenant: workspace.id
      )

    {:ok, task: task, task_state: task_state}
  end

  describe "agent run activities in timeline" do
    test "displays agent run activity with completed status", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, agent_run} =
        Tasks.update_agent_run(
          agent_run,
          %{status: :completed, test_output: "All 5 tests passed"},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id,
        authorize?: false
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Activity"
      assert html =~ "Agent"
      assert html =~ "completed"
    end

    test "displays agent run activity with failed status and error message", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, agent_run} =
        Tasks.update_agent_run(
          agent_run,
          %{status: :failed, error_message: "Test failure: expected 200, got 500"},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id,
        authorize?: false
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "failed"
      assert html =~ "Test failure: expected 200, got 500"
    end

    test "displays commits in collapsible section", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, agent_run} =
        Tasks.update_agent_run(
          agent_run,
          %{
            status: :completed,
            commits: [
              %{"sha" => "abc1234def", "message" => "Fix widget rendering"},
              %{"sha" => "def5678abc", "message" => "Add test coverage"}
            ]
          },
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id,
        authorize?: false
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Commits (2)"
      assert html =~ "abc1234"
      assert html =~ "Fix widget rendering"
      assert html =~ "def5678"
      assert html =~ "Add test coverage"
    end

    test "displays test output in collapsible section", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, agent_run} =
        Tasks.update_agent_run(
          agent_run,
          %{status: :completed, test_output: "12 tests, 0 failures"},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id,
        authorize?: false
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Test Output"
      assert html =~ "12 tests, 0 failures"
    end

    test "shows cancel button for running agent run", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, agent_run} =
        Tasks.update_agent_run(
          agent_run,
          %{status: :running},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id,
        authorize?: false
      )

      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "running"
      assert has_element?(view, "button", "Cancel")
      assert has_element?(view, "a", "Watch")
    end

    test "does not show cancel button for completed agent run", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, agent_run} =
        Tasks.update_agent_run(
          agent_run,
          %{status: :completed},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id,
        authorize?: false
      )

      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      refute has_element?(
               view,
               ~s(button[phx-click="request-cancel-agent-run"])
             )
    end

    test "agent run activities appear alongside comment activities", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      Tasks.create_comment!(
        %{body: "Starting work on this", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      agent_run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, agent_run} =
        Tasks.update_agent_run(
          agent_run,
          %{status: :completed},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id,
        authorize?: false
      )

      Tasks.create_comment!(
        %{body: "Agent finished the work", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "Starting work on this"
      assert html =~ "completed"
      assert html =~ "Agent finished the work"
    end

    test "standalone agent runs section is not present", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, _} =
        Tasks.update_agent_run(
          agent_run,
          %{status: :completed},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id,
        authorize?: false
      )

      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      refute has_element?(view, "#agent-runs-section")
      refute html =~ "Agent Runs"
    end

    test "multiple agent run activities display in timeline", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      run1 =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, run1} =
        Tasks.update_agent_run(
          run1,
          %{status: :failed, error_message: "Tests failed"},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: run1.id},
        tenant: workspace.id,
        authorize?: false
      )

      run2 =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, run2} =
        Tasks.update_agent_run(
          run2,
          %{status: :completed, test_output: "All tests pass"},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: run2.id},
        tenant: workspace.id,
        authorize?: false
      )

      {:ok, _view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "failed"
      assert html =~ "Tests failed"
      assert html =~ "completed"
      assert html =~ "All tests pass"
    end
  end

  describe "agent run activity real-time updates" do
    test "new agent run activity appears via PubSub", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      {:ok, view, html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert html =~ "No activity yet"

      agent_run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, agent_run} =
        Tasks.update_agent_run(
          agent_run,
          %{status: :completed},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id,
        authorize?: false
      )

      assert render(view) =~ "completed"
    end

    test "agent run status update refreshes activity", %{
      conn: conn,
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, agent_run} =
        Tasks.update_agent_run(
          agent_run,
          %{status: :running},
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id,
        authorize?: false
      )

      {:ok, view, _html} = live(conn, ~p"/tasks/#{task.human_id}")

      assert render(view) =~ "running"

      {:ok, _} =
        Tasks.update_agent_run(
          agent_run,
          %{status: :completed, test_output: "All green"},
          actor: user,
          tenant: workspace.id
        )

      # PubSub triggers send_update to the component; render twice to
      # flush both the handle_info and the component update
      render(view)
      html = render(view)
      assert html =~ "completed"
    end
  end
end
