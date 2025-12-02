defmodule Citadel.Tasks.TaskMultitenancyTest do
  @moduledoc """
  Tests for workspace-based multitenancy isolation in tasks.

  These tests verify that:
  - Tasks are properly scoped to workspaces
  - Users can only access tasks in their workspaces
  - Users cannot access tasks in other workspaces
  - Workspace isolation is enforced consistently
  """
  use Citadel.DataCase, async: true

  alias Citadel.{Accounts, Tasks}

  describe "workspace isolation" do
    setup do
      # Create two separate workspaces with different owners
      owner1 = generate(user())
      workspace1 = generate(workspace([], actor: owner1))

      owner2 = generate(user())
      workspace2 = generate(workspace([], actor: owner2))

      # Create a task state
      task_state = Tasks.create_task_state!(%{name: "To Do", order: 1})

      {:ok,
       workspace1: workspace1,
       owner1: owner1,
       workspace2: workspace2,
       owner2: owner2,
       task_state: task_state}
    end

    test "users can only see tasks in their workspaces", context do
      %{workspace1: workspace1, owner1: owner1, task_state: task_state} = context

      # Create task in workspace1
      task =
        generate(
          task(
            [
              workspace_id: workspace1.id,
              task_state_id: task_state.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Owner1 should be able to see their task
      assert {:ok, found_task} = Tasks.get_task(task.id, actor: owner1, tenant: workspace1.id)
      assert found_task.id == task.id
      assert found_task.workspace_id == workspace1.id
    end

    test "users cannot access tasks in other workspaces", context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        workspace2: workspace2,
        owner2: owner2,
        task_state: task_state
      } = context

      # Create task in workspace1
      task =
        generate(
          task(
            [
              workspace_id: workspace1.id,
              task_state_id: task_state.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Owner2 (from different workspace) should NOT be able to see it
      # Note: With multitenancy, querying with wrong tenant returns NotFound, not Forbidden
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.get_task!(task.id, actor: owner2, tenant: workspace2.id)
      end
    end

    test "creating task without workspace raises error", context do
      %{owner1: owner1, task_state: task_state} = context

      # Attempting to create task without workspace_id should fail
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task!(
          %{
            title: "Task without workspace",
            task_state_id: task_state.id
          },
          actor: owner1
        )
      end
    end

    test "user can access tasks in multiple workspaces they are members of", context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        workspace2: workspace2,
        owner2: owner2,
        task_state: task_state
      } = context

      # Create a user who will be a member of both workspaces
      multi_workspace_user = generate(user())

      # Add user to both workspaces
      Accounts.add_workspace_member!(
        multi_workspace_user.id,
        workspace1.id,
        actor: owner1
      )

      Accounts.add_workspace_member!(
        multi_workspace_user.id,
        workspace2.id,
        actor: owner2
      )

      # Create tasks in both workspaces
      task1 =
        generate(
          task(
            [
              workspace_id: workspace1.id,
              task_state_id: task_state.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      task2 =
        generate(
          task(
            [
              workspace_id: workspace2.id,
              task_state_id: task_state.id
            ],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      # Multi-workspace user should be able to see tasks from both workspaces
      assert {:ok, found_task1} =
               Tasks.get_task(task1.id, actor: multi_workspace_user, tenant: workspace1.id)

      assert {:ok, found_task2} =
               Tasks.get_task(task2.id, actor: multi_workspace_user, tenant: workspace2.id)

      assert found_task1.workspace_id == workspace1.id
      assert found_task2.workspace_id == workspace2.id
    end

    test "listing tasks only returns tasks from accessible workspaces", context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        workspace2: workspace2,
        owner2: owner2,
        task_state: task_state
      } = context

      # Create tasks in both workspaces
      _task1 =
        generate(
          task(
            [
              workspace_id: workspace1.id,
              task_state_id: task_state.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      _task2 =
        generate(
          task(
            [
              workspace_id: workspace2.id,
              task_state_id: task_state.id
            ],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      # Owner1 should only see tasks from workspace1
      tasks_for_owner1 = Tasks.list_tasks!(actor: owner1, tenant: workspace1.id)
      assert length(tasks_for_owner1) == 1
      assert Enum.all?(tasks_for_owner1, fn t -> t.workspace_id == workspace1.id end)

      # Owner2 should only see tasks from workspace2
      tasks_for_owner2 = Tasks.list_tasks!(actor: owner2, tenant: workspace2.id)
      assert length(tasks_for_owner2) == 1
      assert Enum.all?(tasks_for_owner2, fn t -> t.workspace_id == workspace2.id end)
    end

    test "updating task in different workspace raises forbidden error", context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        workspace2: workspace2,
        owner2: owner2,
        task_state: task_state
      } = context

      # Create task in workspace1
      task =
        generate(
          task(
            [
              workspace_id: workspace1.id,
              task_state_id: task_state.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Owner2 should not be able to update task from workspace1
      # With multitenancy, wrong tenant returns NotFound/Invalid
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.update_task!(
          task.id,
          %{title: "Hacked title"},
          actor: owner2,
          tenant: workspace2.id
        )
      end
    end

    test "deleting task in different workspace raises forbidden error", context do
      %{
        workspace1: workspace1,
        owner1: owner1,
        workspace2: workspace2,
        owner2: owner2,
        task_state: task_state
      } = context

      # Create task in workspace1
      task =
        generate(
          task(
            [
              workspace_id: workspace1.id,
              task_state_id: task_state.id
            ],
            actor: owner1,
            tenant: workspace1.id
          )
        )

      # Owner2 should not be able to delete task from workspace1
      assert_raise Ash.Error.Forbidden, fn ->
        Ash.destroy!(task, actor: owner2, tenant: workspace2.id)
      end
    end
  end

  describe "workspace membership changes" do
    setup do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))
      task_state = Tasks.create_task_state!(%{name: "To Do", order: 1})

      {:ok, workspace: workspace, owner: owner, task_state: task_state}
    end

    test "leaving workspace removes access to workspace tasks", context do
      %{workspace: workspace, owner: owner, task_state: task_state} = context

      # Create a member
      member = generate(user())

      membership =
        Accounts.add_workspace_member!(member.id, workspace.id, actor: owner)

      # Create task that member can see
      task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: task_state.id
            ],
            actor: owner,
            tenant: workspace.id
          )
        )

      # Member should be able to see the task
      assert {:ok, _} = Tasks.get_task(task.id, actor: member, tenant: workspace.id)

      # Remove member from workspace
      Accounts.remove_workspace_member!(membership, actor: owner)

      # Member should no longer be able to see the task (NotFound)
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.get_task!(task.id, actor: member, tenant: workspace.id)
      end
    end
  end
end
