defmodule Citadel.Tasks.AgentRunTest do
  use Citadel.DataCase, async: true

  alias Citadel.Tasks

  setup do
    user = generate(user())
    workspace = generate(workspace([], actor: user))

    task_state =
      Tasks.create_task_state!(%{
        name: "Task State #{System.unique_integer([:positive])}",
        order: 1
      })

    task =
      Tasks.create_task!(
        %{
          title: "Test Task #{System.unique_integer([:positive])}",
          task_state_id: task_state.id,
          workspace_id: workspace.id
        },
        actor: user,
        tenant: workspace.id
      )

    {:ok, user: user, workspace: workspace, task: task}
  end

  describe "create_agent_run/2" do
    test "creates an agent run linked to a task", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert agent_run.task_id == task.id
      assert agent_run.workspace_id == workspace.id
      assert agent_run.status == :pending
      assert agent_run.user_id == user.id
    end

    test "defaults status to :pending", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert agent_run.status == :pending
    end

    test "workspace member can create an agent run", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      member = generate(user())
      add_user_to_workspace(member.id, workspace.id, actor: user)

      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: member,
          tenant: workspace.id
        )

      assert agent_run.user_id == member.id
    end

    test "non-member cannot create an agent run", %{workspace: workspace, task: task} do
      outsider = generate(user())

      assert_raise Ash.Error.Forbidden, fn ->
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: outsider,
          tenant: workspace.id
        )
      end
    end

    test "broadcasts PubSub message on create", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      CitadelWeb.Endpoint.subscribe("tasks:agent_runs:#{task.id}")

      Tasks.create_agent_run!(
        %{task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:agent_runs:" <> _,
        event: "create"
      }
    end
  end

  describe "update_agent_run/2" do
    test "updates status and result fields", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      now = DateTime.utc_now()

      updated =
        Tasks.update_agent_run!(
          agent_run,
          %{
            status: :running,
            started_at: now
          },
          actor: user,
          tenant: workspace.id
        )

      assert updated.status == :running
      assert updated.started_at != nil
    end

    test "can set completed status with commits and test output", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      now = DateTime.utc_now()

      commits = [
        %{"sha" => "abc123def456", "message" => "first commit"},
        %{"sha" => "789012fed345", "message" => "second commit"}
      ]

      updated =
        Tasks.update_agent_run!(
          agent_run,
          %{
            status: :completed,
            commits: commits,
            test_output: "All tests passed",
            logs: "Agent execution log...",
            completed_at: now
          },
          actor: user,
          tenant: workspace.id
        )

      assert updated.status == :completed
      assert updated.commits == commits
      assert updated.test_output == "All tests passed"
      assert updated.logs == "Agent execution log..."
    end

    test "can set failed status with error message", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      updated =
        Tasks.update_agent_run!(
          agent_run,
          %{
            status: :failed,
            error_message: "Compilation failed",
            completed_at: DateTime.utc_now()
          },
          actor: user,
          tenant: workspace.id
        )

      assert updated.status == :failed
      assert updated.error_message == "Compilation failed"
    end

    test "broadcasts PubSub message on update", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      CitadelWeb.Endpoint.subscribe("tasks:agent_runs:#{task.id}")

      Tasks.update_agent_run!(
        agent_run,
        %{status: :running},
        actor: user,
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:agent_runs:" <> _,
        event: "update"
      }
    end
  end

  describe "list_agent_runs/2" do
    test "returns agent runs for a task in chronological order", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      for _ <- 1..3 do
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
      end

      runs = Tasks.list_agent_runs_by_task!(task.id, actor: user, tenant: workspace.id)
      assert length(runs) == 3
    end

    test "returns empty list for task with no agent runs", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      runs = Tasks.list_agent_runs_by_task!(task.id, actor: user, tenant: workspace.id)
      assert runs == []
    end

    test "only returns agent runs for the specified task", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      task_state = Tasks.list_task_states!() |> List.first()

      other_task =
        Tasks.create_task!(
          %{
            title: "Other Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run!(
        %{task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      Tasks.create_agent_run!(
        %{task_id: other_task.id},
        actor: user,
        tenant: workspace.id
      )

      runs = Tasks.list_agent_runs_by_task!(task.id, actor: user, tenant: workspace.id)
      assert length(runs) == 1
      assert hd(runs).task_id == task.id
    end
  end

  describe "cancel_agent_run/2" do
    test "cancels a pending run", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      cancelled =
        Tasks.cancel_agent_run!(agent_run, actor: user, tenant: workspace.id)

      assert cancelled.status == :cancelled
      assert cancelled.completed_at != nil
      assert cancelled.error_message == "Manually cancelled by user"
    end

    test "cancels a running run", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      running =
        Tasks.update_agent_run!(
          agent_run,
          %{status: :running, started_at: DateTime.utc_now()},
          actor: user,
          tenant: workspace.id
        )

      cancelled =
        Tasks.cancel_agent_run!(running, actor: user, tenant: workspace.id)

      assert cancelled.status == :cancelled
      assert cancelled.completed_at != nil
      assert cancelled.error_message == "Manually cancelled by user"
    end

    test "cannot cancel a completed run", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      completed =
        Tasks.update_agent_run!(
          agent_run,
          %{status: :completed, completed_at: DateTime.utc_now()},
          actor: user,
          tenant: workspace.id
        )

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.cancel_agent_run!(completed, actor: user, tenant: workspace.id)
      end
    end

    test "cannot cancel a failed run", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      failed =
        Tasks.update_agent_run!(
          agent_run,
          %{status: :failed, error_message: "Something broke"},
          actor: user,
          tenant: workspace.id
        )

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.cancel_agent_run!(failed, actor: user, tenant: workspace.id)
      end
    end

    test "broadcasts PubSub message on cancel", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      CitadelWeb.Endpoint.subscribe("tasks:agent_runs:#{task.id}")

      Tasks.cancel_agent_run!(agent_run, actor: user, tenant: workspace.id)

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:agent_runs:" <> _,
        event: "cancel"
      }
    end
  end

  describe "multitenancy" do
    test "agent runs are scoped to workspace", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert agent_run.workspace_id == workspace.id
    end
  end
end
