defmodule Citadel.Tasks.AgentWorkItemTest do
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

  describe "create_agent_work_item/2" do
    test "creates a new_task work item", %{user: user, workspace: workspace, task: task} do
      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert work_item.type == :new_task
      assert work_item.status == :pending
      assert work_item.task_id == task.id
      assert work_item.workspace_id == workspace.id
    end

    test "creates a changes_requested work item with comment", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      comment =
        Tasks.create_comment!(
          %{body: "Please fix this", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      work_item =
        Tasks.create_agent_work_item!(
          %{type: :changes_requested, task_id: task.id, comment_id: comment.id},
          actor: user,
          tenant: workspace.id
        )

      assert work_item.type == :changes_requested
      assert work_item.comment_id == comment.id
    end

    test "non-member cannot create a work item", %{workspace: workspace, task: task} do
      outsider = generate(user())

      assert_raise Ash.Error.Forbidden, fn ->
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: outsider,
          tenant: workspace.id
        )
      end
    end

    test "broadcasts PubSub message on create", %{user: user, workspace: workspace, task: task} do
      CitadelWeb.Endpoint.subscribe("tasks:agent_work_items:#{task.id}")

      Tasks.create_agent_work_item!(
        %{type: :new_task, task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:agent_work_items:" <> _,
        event: "create"
      }
    end
  end

  describe "uniqueness constraint" do
    test "prevents two active work items for the same task", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      Tasks.create_agent_work_item!(
        %{type: :new_task, task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_agent_work_item!(
          %{type: :changes_requested, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
      end
    end

    test "allows new work item after previous one is completed", %{
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

      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      work_item =
        Tasks.claim_agent_work_item!(work_item, %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      Tasks.complete_agent_work_item!(work_item, actor: user, tenant: workspace.id)

      new_item =
        Tasks.create_agent_work_item!(
          %{type: :changes_requested, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert new_item.status == :pending
    end

    test "allows new work item after previous one is cancelled", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      Tasks.cancel_agent_work_item!(work_item, actor: user, tenant: workspace.id)

      new_item =
        Tasks.create_agent_work_item!(
          %{type: :changes_requested, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert new_item.status == :pending
    end
  end

  describe "claim_agent_work_item/2" do
    test "transitions pending to claimed with agent_run_id", %{
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

      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      claimed =
        Tasks.claim_agent_work_item!(work_item, %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      assert claimed.status == :claimed
      assert claimed.agent_run_id == agent_run.id
    end

    test "cannot claim a non-pending work item", %{
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

      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      claimed =
        Tasks.claim_agent_work_item!(work_item, %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.claim_agent_work_item!(claimed, %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )
      end
    end
  end

  describe "complete_agent_work_item/2" do
    test "transitions claimed to completed", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      claimed =
        Tasks.claim_agent_work_item!(work_item, %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      completed =
        Tasks.complete_agent_work_item!(claimed, actor: user, tenant: workspace.id)

      assert completed.status == :completed
    end

    test "cannot complete a pending work item", %{user: user, workspace: workspace, task: task} do
      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.complete_agent_work_item!(work_item, actor: user, tenant: workspace.id)
      end
    end
  end

  describe "cancel_agent_work_item/2" do
    test "cancels a pending work item", %{user: user, workspace: workspace, task: task} do
      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      cancelled =
        Tasks.cancel_agent_work_item!(work_item, actor: user, tenant: workspace.id)

      assert cancelled.status == :cancelled
    end

    test "cancels a claimed work item", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      claimed =
        Tasks.claim_agent_work_item!(work_item, %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      cancelled =
        Tasks.cancel_agent_work_item!(claimed, actor: user, tenant: workspace.id)

      assert cancelled.status == :cancelled
    end

    test "cannot cancel a completed work item", %{user: user, workspace: workspace, task: task} do
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      claimed =
        Tasks.claim_agent_work_item!(work_item, %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      completed =
        Tasks.complete_agent_work_item!(claimed, actor: user, tenant: workspace.id)

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.cancel_agent_work_item!(completed, actor: user, tenant: workspace.id)
      end
    end
  end

  describe "multitenancy" do
    test "work items are scoped to workspace", %{user: user, workspace: workspace, task: task} do
      work_item =
        Tasks.create_agent_work_item!(
          %{type: :new_task, task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert work_item.workspace_id == workspace.id
    end
  end
end
