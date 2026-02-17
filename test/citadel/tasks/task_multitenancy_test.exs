defmodule Citadel.Tasks.TaskMultitenancyTest do
  @moduledoc """
  Tests for workspace-based multitenancy isolation in tasks.

  These tests verify that:
  - Tasks are properly scoped to workspaces
  - Users can only access tasks in their workspaces
  - Users cannot access tasks in other workspaces
  - Workspace isolation is enforced consistently
  """
  use Citadel.DataCase, async: false

  alias Citadel.{Accounts, Tasks}

  describe "workspace isolation" do
    setup do
      owner1 = generate(user())
      org1 = generate(organization([], actor: owner1))
      workspace1 = generate(workspace([organization_id: org1.id], actor: owner1))

      owner2 = generate(user())
      org2 = generate(organization([], actor: owner2))
      workspace2 = generate(workspace([organization_id: org2.id], actor: owner2))

      task_state = Tasks.create_task_state!(%{name: "To Do", order: 1})

      {:ok,
       workspace1: workspace1,
       owner1: owner1,
       org1: org1,
       workspace2: workspace2,
       owner2: owner2,
       org2: org2,
       task_state: task_state}
    end

    test "users can only see tasks in their workspaces", context do
      %{workspace1: workspace1, owner1: owner1, task_state: task_state} = context

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

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.get_task!(task.id, actor: owner2, tenant: workspace2.id)
      end
    end

    test "creating task without workspace raises error", context do
      %{owner1: owner1, task_state: task_state} = context

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
        org1: org1,
        workspace2: workspace2,
        owner2: owner2,
        org2: org2,
        task_state: task_state
      } = context

      upgrade_to_pro(org1)
      upgrade_to_pro(org2)

      multi_workspace_user = generate(user())

      add_user_to_workspace(multi_workspace_user.id, workspace1.id, actor: owner1)
      add_user_to_workspace(multi_workspace_user.id, workspace2.id, actor: owner2)

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

      tasks_for_owner1 = Tasks.list_tasks!(actor: owner1, tenant: workspace1.id)
      assert length(tasks_for_owner1) == 1
      assert Enum.all?(tasks_for_owner1, fn t -> t.workspace_id == workspace1.id end)

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

      assert_raise Ash.Error.Forbidden, fn ->
        Ash.destroy!(task, actor: owner2, tenant: workspace2.id)
      end
    end
  end

  describe "workspace membership changes" do
    setup do
      owner = generate(user())
      org = generate(organization([], actor: owner))
      upgrade_to_pro(org)
      workspace = generate(workspace([organization_id: org.id], actor: owner))
      task_state = Tasks.create_task_state!(%{name: "To Do", order: 1})

      {:ok, workspace: workspace, owner: owner, org: org, task_state: task_state}
    end

    test "leaving workspace removes access to workspace tasks", context do
      %{workspace: workspace, owner: owner, task_state: task_state} = context

      member = generate(user())

      membership = add_user_to_workspace(member.id, workspace.id, actor: owner)

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

      assert {:ok, _} = Tasks.get_task(task.id, actor: member, tenant: workspace.id)

      Accounts.remove_workspace_member!(membership, actor: owner)

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.get_task!(task.id, actor: member, tenant: workspace.id)
      end
    end
  end
end
