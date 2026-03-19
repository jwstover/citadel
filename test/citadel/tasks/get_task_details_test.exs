defmodule Citadel.Tasks.GetTaskDetailsTest do
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

    {:ok, user: user, workspace: workspace, task_state: task_state}
  end

  describe "get_task_details/2" do
    test "returns formatted details for a task", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Test Task #{System.unique_integer([:positive])}",
            description: "A detailed description",
            task_state_id: task_state.id,
            priority: :high,
            due_date: ~D[2026-04-01]
          },
          actor: user,
          tenant: workspace.id
        )

      result =
        Tasks.get_task_details!(task.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert is_binary(result)
      assert result =~ task.human_id
      assert result =~ task.title
      assert result =~ "A detailed description"
      assert result =~ task_state.name
      assert result =~ "high"
      assert result =~ "2026-04-01"
    end

    test "includes parent task info", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      parent =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user,
          tenant: workspace.id
        )

      child =
        Tasks.create_task!(
          %{
            title: "Child Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent.id
          },
          actor: user,
          tenant: workspace.id
        )

      result =
        Tasks.get_task_details!(child.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert result =~ parent.human_id
      assert result =~ parent.title
    end

    test "includes sub-tasks", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      parent =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_task =
        Tasks.create_task!(
          %{
            title: "Sub Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent.id
          },
          actor: user,
          tenant: workspace.id
        )

      result =
        Tasks.get_task_details!(parent.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert result =~ sub_task.human_id
      assert result =~ sub_task.title
    end

    test "includes assignees", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Assigned Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            assignees: [user.id]
          },
          actor: user,
          tenant: workspace.id
        )

      result =
        Tasks.get_task_details!(task.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert result =~ to_string(user.email)
    end

    test "includes dependencies", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      dep_task =
        Tasks.create_task!(
          %{
            title: "Dependency Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user,
          tenant: workspace.id
        )

      task =
        Tasks.create_task!(
          %{
            title: "Blocked Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            dependencies: [dep_task.id]
          },
          actor: user,
          tenant: workspace.id
        )

      result =
        Tasks.get_task_details!(task.human_id,
          actor: user,
          tenant: workspace.id
        )

      assert result =~ dep_task.human_id
      assert result =~ dep_task.title
    end

    test "returns error for non-existent human_id", %{
      user: user,
      workspace: workspace
    } do
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.get_task_details!("NONEXISTENT-999",
          actor: user,
          tenant: workspace.id
        )
      end
    end

    test "respects multitenancy - cannot access tasks from another workspace", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Tenant Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user,
          tenant: workspace.id
        )

      other_user = generate(user())
      other_workspace = generate(workspace([], actor: other_user))

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.get_task_details!(task.human_id,
          actor: other_user,
          tenant: other_workspace.id
        )
      end
    end
  end
end
