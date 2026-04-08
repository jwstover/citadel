defmodule Citadel.Tasks.Changes.MaybeEnqueueAgentWorkTest do
  use Citadel.DataCase, async: true

  alias Citadel.Tasks

  require Ash.Query

  setup do
    user = generate(user())
    workspace = generate(workspace([], actor: user))

    backlog_state =
      case Citadel.Tasks.TaskState
           |> Ash.Query.filter(name == "Backlog")
           |> Ash.read_one(authorize?: false) do
        {:ok, nil} ->
          Tasks.create_task_state!(%{name: "Backlog", order: 0, is_complete: false})

        {:ok, state} ->
          state
      end

    todo_state =
      Tasks.create_task_state!(%{
        name: "To Do #{System.unique_integer([:positive])}",
        order: 1,
        is_complete: false
      })

    in_progress_state =
      Tasks.create_task_state!(%{
        name: "In Progress #{System.unique_integer([:positive])}",
        order: 2,
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
     in_progress_state: in_progress_state,
     in_review_state: in_review_state,
     backlog_state: backlog_state,
     done_state: done_state}
  end

  describe "task creation" do
    test "creates work item when task is agent_eligible with workable state", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Agent Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      work_items = list_work_items_for_task(task.id, workspace.id)
      assert length(work_items) == 1
      assert hd(work_items).type == :new_task
      assert hd(work_items).status == :pending
    end

    test "does not create work item when agent_eligible is false", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Non-Agent Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false
          },
          actor: user,
          tenant: workspace.id
        )

      work_items = list_work_items_for_task(task.id, workspace.id)
      assert work_items == []
    end

    test "does not create work item when task state is complete", %{
      user: user,
      workspace: workspace,
      done_state: done_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Done Task #{System.unique_integer([:positive])}",
            task_state_id: done_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      work_items = list_work_items_for_task(task.id, workspace.id)
      assert work_items == []
    end

    test "does not create work item when task state is Backlog", %{
      user: user,
      workspace: workspace,
      backlog_state: backlog_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Backlog Task #{System.unique_integer([:positive])}",
            task_state_id: backlog_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      work_items = list_work_items_for_task(task.id, workspace.id)
      assert work_items == []
    end

    test "does not create work item when task state is In Review", %{
      user: user,
      workspace: workspace,
      in_review_state: in_review_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Review Task #{System.unique_integer([:positive])}",
            task_state_id: in_review_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      work_items = list_work_items_for_task(task.id, workspace.id)
      assert work_items == []
    end
  end

  describe "task update" do
    test "creates work item when agent_eligible toggled to true", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Toggle Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false
          },
          actor: user,
          tenant: workspace.id
        )

      assert list_work_items_for_task(task.id, workspace.id) == []

      Tasks.update_task!(task.id, %{agent_eligible: true}, actor: user, tenant: workspace.id)

      work_items = list_work_items_for_task(task.id, workspace.id)
      assert length(work_items) == 1
    end

    test "creates work item when state changed from Backlog to workable", %{
      user: user,
      workspace: workspace,
      backlog_state: backlog_state,
      todo_state: todo_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Backlog to Todo #{System.unique_integer([:positive])}",
            task_state_id: backlog_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      assert list_work_items_for_task(task.id, workspace.id) == []

      Tasks.update_task!(task.id, %{task_state_id: todo_state.id},
        actor: user,
        tenant: workspace.id
      )

      work_items = list_work_items_for_task(task.id, workspace.id)
      assert length(work_items) == 1
    end

    test "creates work item when state changed from In Review to workable", %{
      user: user,
      workspace: workspace,
      in_review_state: in_review_state,
      in_progress_state: in_progress_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Review to Progress #{System.unique_integer([:positive])}",
            task_state_id: in_review_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      assert list_work_items_for_task(task.id, workspace.id) == []

      Tasks.update_task!(task.id, %{task_state_id: in_progress_state.id},
        actor: user,
        tenant: workspace.id
      )

      work_items = list_work_items_for_task(task.id, workspace.id)
      assert length(work_items) == 1
    end

    test "does not create duplicate work items", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "No Dup Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      assert length(list_work_items_for_task(task.id, workspace.id)) == 1

      Tasks.update_task!(task.id, %{title: "Updated title"},
        actor: user,
        tenant: workspace.id
      )

      assert length(list_work_items_for_task(task.id, workspace.id)) == 1
    end

    test "does not create work item when active run exists", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Active Run Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false
          },
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_agent_run!(
        %{task_id: task.id, status: :running},
        actor: user,
        tenant: workspace.id
      )

      Tasks.update_task!(task.id, %{agent_eligible: true}, actor: user, tenant: workspace.id)

      assert list_work_items_for_task(task.id, workspace.id) == []
    end

    test "creates new work item when toggling agent_eligible after claimed work item is cancelled", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Cancelled Run Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      work_items = list_work_items_for_task(task.id, workspace.id)
      assert length(work_items) == 1
      original_work_item = hd(work_items)

      # Simulate the claim flow: create agent run and claim the work item
      agent_run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      original_work_item
      |> Ash.Changeset.for_update(:claim, %{agent_run_id: agent_run.id},
        authorize?: false,
        tenant: workspace.id
      )
      |> Ash.update!()

      # Cancel the agent run (which cancels the claimed work item via SyncWorkItemStatus)
      Tasks.cancel_agent_run!(agent_run, actor: user, tenant: workspace.id)

      # Verify work item was cancelled
      work_items = list_work_items_for_task(task.id, workspace.id)
      assert Enum.all?(work_items, &(&1.status == :cancelled))

      # Toggle agent_eligible off then on - should create a new pending work item
      Tasks.update_task!(task.id, %{agent_eligible: false}, actor: user, tenant: workspace.id)
      Tasks.update_task!(task.id, %{agent_eligible: true}, actor: user, tenant: workspace.id)

      work_items = list_work_items_for_task(task.id, workspace.id)
      pending_items = Enum.filter(work_items, &(&1.status == :pending))
      assert length(pending_items) == 1
      assert hd(pending_items).id != original_work_item.id
    end
  end

  describe "dependency-blocked tasks" do
    test "does not create work item when task has incomplete dependency on create", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      blocking_task =
        Tasks.create_task!(
          %{
            title: "Blocker #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false
          },
          actor: user,
          tenant: workspace.id
        )

      dependent_task =
        Tasks.create_task!(
          %{
            title: "Blocked Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true,
            dependencies: [blocking_task.id]
          },
          actor: user,
          tenant: workspace.id
        )

      assert list_work_items_for_task(dependent_task.id, workspace.id) == []
    end

    test "does not create work item when task has incomplete dependency on update", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      blocking_task =
        Tasks.create_task!(
          %{
            title: "Blocker #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false
          },
          actor: user,
          tenant: workspace.id
        )

      dependent_task =
        Tasks.create_task!(
          %{
            title: "Blocked Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false,
            dependencies: [blocking_task.id]
          },
          actor: user,
          tenant: workspace.id
        )

      Tasks.update_task!(dependent_task.id, %{agent_eligible: true},
        actor: user,
        tenant: workspace.id
      )

      assert list_work_items_for_task(dependent_task.id, workspace.id) == []
    end

    test "completing a blocking task enqueues work for unblocked dependent", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state,
      done_state: done_state
    } do
      blocking_task =
        Tasks.create_task!(
          %{
            title: "Blocker #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false
          },
          actor: user,
          tenant: workspace.id
        )

      dependent_task =
        Tasks.create_task!(
          %{
            title: "Blocked Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true,
            dependencies: [blocking_task.id]
          },
          actor: user,
          tenant: workspace.id
        )

      assert list_work_items_for_task(dependent_task.id, workspace.id) == []

      Tasks.update_task!(blocking_task.id, %{task_state_id: done_state.id},
        actor: user,
        tenant: workspace.id
      )

      work_items = list_work_items_for_task(dependent_task.id, workspace.id)
      assert length(work_items) == 1
      assert hd(work_items).type == :new_task
      assert hd(work_items).status == :pending
    end

    test "completing a blocking task does not enqueue dependent still blocked by another task", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state,
      done_state: done_state
    } do
      blocker_a =
        Tasks.create_task!(
          %{
            title: "Blocker A #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false
          },
          actor: user,
          tenant: workspace.id
        )

      blocker_b =
        Tasks.create_task!(
          %{
            title: "Blocker B #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false
          },
          actor: user,
          tenant: workspace.id
        )

      dependent_task =
        Tasks.create_task!(
          %{
            title: "Double Blocked #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true,
            dependencies: [blocker_a.id, blocker_b.id]
          },
          actor: user,
          tenant: workspace.id
        )

      Tasks.update_task!(blocker_a.id, %{task_state_id: done_state.id},
        actor: user,
        tenant: workspace.id
      )

      assert list_work_items_for_task(dependent_task.id, workspace.id) == []
    end

    test "completing a blocking task does not enqueue non-agent-eligible dependent", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state,
      done_state: done_state
    } do
      blocking_task =
        Tasks.create_task!(
          %{
            title: "Blocker #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false
          },
          actor: user,
          tenant: workspace.id
        )

      dependent_task =
        Tasks.create_task!(
          %{
            title: "Non-Agent Dep #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: false,
            dependencies: [blocking_task.id]
          },
          actor: user,
          tenant: workspace.id
        )

      Tasks.update_task!(blocking_task.id, %{task_state_id: done_state.id},
        actor: user,
        tenant: workspace.id
      )

      assert list_work_items_for_task(dependent_task.id, workspace.id) == []
    end
  end

  describe "task completion cancels work items" do
    test "cancels pending work items when task moves to complete state", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state,
      done_state: done_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Complete Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            agent_eligible: true
          },
          actor: user,
          tenant: workspace.id
        )

      assert length(list_work_items_for_task(task.id, workspace.id)) == 1

      Tasks.update_task!(task.id, %{task_state_id: done_state.id},
        actor: user,
        tenant: workspace.id
      )

      work_items = list_work_items_for_task(task.id, workspace.id)
      assert length(work_items) == 1
      assert hd(work_items).status == :cancelled
    end
  end

  defp list_work_items_for_task(task_id, workspace_id) do
    Citadel.Tasks.AgentWorkItem
    |> Ash.Query.filter(task_id == ^task_id)
    |> Ash.read!(authorize?: false, tenant: workspace_id)
  end
end
