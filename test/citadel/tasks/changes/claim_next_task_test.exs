defmodule Citadel.Tasks.Changes.ClaimNextTaskTest do
  use Citadel.DataCase, async: true

  alias Citadel.Tasks

  require Ash.Query

  setup do
    user = generate(user())
    workspace = generate(workspace([], actor: user))

    todo_state =
      Tasks.create_task_state!(%{
        name: "To Do #{System.unique_integer([:positive])}",
        order: 1,
        is_complete: false
      })

    in_review_state =
      case Citadel.Tasks.TaskState
           |> Ash.Query.filter(name == "In Review")
           |> Ash.read_one(authorize?: false) do
        {:ok, nil} ->
          Tasks.create_task_state!(%{name: "In Review", order: 3, is_complete: false})

        {:ok, state} ->
          state
      end

    backlog_state =
      case Citadel.Tasks.TaskState
           |> Ash.Query.filter(name == "Backlog")
           |> Ash.read_one(authorize?: false) do
        {:ok, nil} ->
          Tasks.create_task_state!(%{name: "Backlog", order: 0, is_complete: false})

        {:ok, state} ->
          state
      end

    done_state =
      Tasks.create_task_state!(%{
        name: "Done #{System.unique_integer([:positive])}",
        order: 4,
        is_complete: true
      })

    {:ok,
     user: user,
     workspace: workspace,
     todo_state: todo_state,
     in_review_state: in_review_state,
     backlog_state: backlog_state,
     done_state: done_state}
  end

  describe "claim_next_task" do
    test "claims from the work queue", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Claimable #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      agent_run = Tasks.claim_next_task!(actor: user, tenant: workspace.id)

      assert agent_run.task_id == task.id
      assert agent_run.status == :running

      work_items =
        Citadel.Tasks.AgentWorkItem
        |> Ash.Query.filter(task_id == ^task.id)
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert length(work_items) == 1
      claimed = hd(work_items)
      assert claimed.status == :claimed
      assert claimed.agent_run_id == agent_run.id
    end

    test "returns error when no work items available", %{user: user, workspace: workspace} do
      assert_raise Ash.Error.Invalid, ~r/no tasks available/, fn ->
        Tasks.claim_next_task!(actor: user, tenant: workspace.id)
      end
    end

    test "skips work items for tasks with incomplete dependencies", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      dep_task =
        Tasks.create_task!(
          %{
            title: "Dep Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id
          },
          actor: user,
          tenant: workspace.id
        )

      _blocked_task =
        Tasks.create_task!(
          %{
            title: "Blocked Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true,
            dependencies: [dep_task.id]
          },
          actor: user,
          tenant: workspace.id
        )

      assert_raise Ash.Error.Invalid, ~r/no tasks available/, fn ->
        Tasks.claim_next_task!(actor: user, tenant: workspace.id)
      end
    end

    test "skips work items for tasks in Backlog state", %{
      user: user,
      workspace: workspace,
      backlog_state: backlog_state
    } do
      _backlog_task =
        Tasks.create_task!(
          %{
            title: "Backlog Task #{System.unique_integer([:positive])}",
            task_state_id: backlog_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      # Backlog prevents work item creation, but even if one existed via
      # a state transition, the claim query should still exclude it.
      # Since no work item is created for Backlog tasks, claiming should fail.
      assert_raise Ash.Error.Invalid, ~r/no tasks available/, fn ->
        Tasks.claim_next_task!(actor: user, tenant: workspace.id)
      end
    end

    test "skips Backlog tasks even when work item exists from prior state", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state,
      backlog_state: backlog_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Regressed Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      work_items =
        Citadel.Tasks.AgentWorkItem
        |> Ash.Query.filter(task_id == ^task.id)
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert length(work_items) == 1

      Tasks.update_task!(task.id, %{task_state_id: backlog_state.id},
        actor: user,
        tenant: workspace.id
      )

      assert_raise Ash.Error.Invalid, ~r/no tasks available/, fn ->
        Tasks.claim_next_task!(actor: user, tenant: workspace.id)
      end
    end

    test "claims higher priority tasks first", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      _low =
        Tasks.create_task!(
          %{
            title: "Low #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true,
            priority: :low
          },
          actor: user,
          tenant: workspace.id
        )

      high =
        Tasks.create_task!(
          %{
            title: "High #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true,
            priority: :high
          },
          actor: user,
          tenant: workspace.id
        )

      agent_run = Tasks.claim_next_task!(actor: user, tenant: workspace.id)
      assert agent_run.task_id == high.id
    end
  end

  describe "agent run lifecycle updates work items" do
    test "completing an agent run completes the work item", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      _task =
        Tasks.create_task!(
          %{
            title: "Lifecycle #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      agent_run = Tasks.claim_next_task!(actor: user, tenant: workspace.id)

      Tasks.update_agent_run!(
        agent_run,
        %{status: :completed, completed_at: DateTime.utc_now()},
        actor: user,
        tenant: workspace.id
      )

      work_items =
        Citadel.Tasks.AgentWorkItem
        |> Ash.Query.filter(agent_run_id == ^agent_run.id)
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert hd(work_items).status == :completed
    end

    test "failing an agent run completes the work item", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      _task =
        Tasks.create_task!(
          %{
            title: "Fail #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      agent_run = Tasks.claim_next_task!(actor: user, tenant: workspace.id)

      Tasks.update_agent_run!(
        agent_run,
        %{status: :failed, error_message: "oops"},
        actor: user,
        tenant: workspace.id
      )

      work_items =
        Citadel.Tasks.AgentWorkItem
        |> Ash.Query.filter(agent_run_id == ^agent_run.id)
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert hd(work_items).status == :completed
    end

    test "cancelling an agent run cancels the work item", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      _task =
        Tasks.create_task!(
          %{
            title: "Cancel #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      agent_run = Tasks.claim_next_task!(actor: user, tenant: workspace.id)

      Tasks.cancel_agent_run!(agent_run, actor: user, tenant: workspace.id)

      work_items =
        Citadel.Tasks.AgentWorkItem
        |> Ash.Query.filter(agent_run_id == ^agent_run.id)
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert hd(work_items).status == :cancelled
    end
  end
end
