defmodule Citadel.Tasks.TaskTest do
  use Citadel.DataCase, async: true

  alias Citadel.{Accounts, Tasks}

  setup do
    # Create a user and workspace for testing
    user = generate(user())
    workspace = generate(workspace([], actor: user))

    # Create a task state for testing
    task_state =
      Tasks.create_task_state!(%{
        name: "Task State #{System.unique_integer([:positive])}",
        order: 1
      })

    {:ok, user: user, workspace: workspace, task_state: task_state}
  end

  describe "create_task/2" do
    test "creates a task with valid attributes", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      attrs = %{
        title: "Test Task #{System.unique_integer([:positive])}",
        description: "A test task",
        task_state_id: task_state.id,
        workspace_id: workspace.id
      }

      assert task = Tasks.create_task!(attrs, actor: user, tenant: workspace.id)
      assert task.title == attrs.title
      assert task.description == attrs.description
      assert task.task_state_id == task_state.id
      assert task.workspace_id == workspace.id
      assert task.user_id == user.id
    end

    test "creates a task without optional description", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      attrs = %{
        title: "Minimal Task #{System.unique_integer([:positive])}",
        task_state_id: task_state.id,
        workspace_id: workspace.id
      }

      assert task = Tasks.create_task!(attrs, actor: user, tenant: workspace.id)
      assert task.title == attrs.title
      assert is_nil(task.description)
    end

    test "raises error when title is missing", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      attrs = %{
        task_state_id: task_state.id,
        workspace_id: workspace.id
      }

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task!(attrs, actor: user, tenant: workspace.id)
      end
    end

    test "sets default task_state_id to the state with lowest order when not provided", %{
      user: user,
      workspace: workspace
    } do
      # Create a task state with the lowest order to ensure it gets selected
      lowest_order_state =
        Tasks.create_task_state!(%{
          name: "Lowest Order State #{System.unique_integer([:positive])}",
          order: 0
        })

      # Create additional task states with higher order
      _higher_order_state =
        Tasks.create_task_state!(%{
          name: "Higher Order State #{System.unique_integer([:positive])}",
          order: 5
        })

      attrs = %{
        title: "Task Without State #{System.unique_integer([:positive])}",
        workspace_id: workspace.id
      }

      task = Tasks.create_task!(attrs, actor: user, tenant: workspace.id)

      # Should default to the task_state with order: 0
      assert task.task_state_id == lowest_order_state.id
    end

    test "raises error when actor is missing", %{workspace: workspace, task_state: task_state} do
      attrs = %{
        title: "Missing User #{System.unique_integer([:positive])}",
        task_state_id: task_state.id,
        workspace_id: workspace.id
      }

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task!(attrs, tenant: workspace.id)
      end
    end
  end

  describe "list_tasks/1" do
    test "returns tasks for the actor user", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      # Create tasks for this user
      task1 =
        Tasks.create_task!(
          %{
            title: "Task 1 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      task2 =
        Tasks.create_task!(
          %{
            title: "Task 2 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # List tasks as this user
      tasks = Tasks.list_tasks!(actor: user, tenant: workspace.id)
      task_ids = Enum.map(tasks, & &1.id)

      assert task1.id in task_ids
      assert task2.id in task_ids
    end

    test "workspace members can see all tasks in the workspace", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      # Create another user and add them as a workspace member
      other_user = create_user()
      Accounts.add_workspace_member!(other_user.id, workspace.id, actor: user)

      # Create task by the other user
      other_task =
        Tasks.create_task!(
          %{
            title: "Other User Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: other_user,
          tenant: workspace.id
        )

      # Create task by the first user
      user_task =
        Tasks.create_task!(
          %{
            title: "User Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Both users can see all tasks in the workspace
      tasks = Tasks.list_tasks!(actor: user, tenant: workspace.id)
      task_ids = Enum.map(tasks, & &1.id)

      assert user_task.id in task_ids
      assert other_task.id in task_ids
    end

    test "returns empty list when user has no tasks", %{user: user, workspace: workspace} do
      tasks = Tasks.list_tasks!(actor: user, tenant: workspace.id)
      assert tasks == []
    end

    test "can filter tasks by task_state", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      # Create another task state
      other_state =
        Tasks.create_task_state!(%{
          name: "Other State #{System.unique_integer([:positive])}",
          order: 2
        })

      # Create tasks with different states
      task1 =
        Tasks.create_task!(
          %{
            title: "Task State 1 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      _task2 =
        Tasks.create_task!(
          %{
            title: "Task State 2 #{System.unique_integer([:positive])}",
            task_state_id: other_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Filter by first task state
      tasks =
        Tasks.list_tasks!(
          actor: user,
          tenant: workspace.id,
          query: [filter: [task_state_id: task_state.id]]
        )

      assert length(tasks) == 1
      assert hd(tasks).id == task1.id
    end

    test "can load relationships", %{user: user, workspace: workspace, task_state: task_state} do
      task =
        Tasks.create_task!(
          %{
            title: "Task with Relations #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      tasks =
        Tasks.list_tasks!(
          actor: user,
          tenant: workspace.id,
          query: [filter: [id: task.id]],
          load: [:task_state, :user]
        )

      assert length(tasks) == 1
      loaded_task = hd(tasks)
      assert loaded_task.task_state.id == task_state.id
      assert loaded_task.user.id == user.id
    end
  end

  describe "update task" do
    test "updates a task with valid attributes", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Original Title #{System.unique_integer([:positive])}",
            description: "Original description",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      updated =
        Ash.update!(
          task,
          %{
            title: "Updated Title #{System.unique_integer([:positive])}",
            description: "Updated description"
          },
          actor: user,
          tenant: workspace.id
        )

      assert updated.id == task.id
      assert updated.title != task.title
      assert updated.description == "Updated description"
    end

    test "can change task_state", %{user: user, workspace: workspace, task_state: task_state} do
      # Create another task state
      new_state =
        Tasks.create_task_state!(%{
          name: "New State #{System.unique_integer([:positive])}",
          order: 2
        })

      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      updated =
        Ash.update!(task, %{task_state_id: new_state.id}, actor: user, tenant: workspace.id)

      assert updated.task_state_id == new_state.id
    end

    test "raises error when updating without authorization", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      # Create another user with their own workspace
      other_user = generate(user())
      other_workspace = generate(workspace([], actor: other_user))

      # Create task owned by the first user
      task =
        Tasks.create_task!(
          %{
            title: "Protected Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Try to update as the other user (with their own workspace tenant)
      # Will get NotFound/Invalid because task doesn't exist in their workspace
      assert_raise Ash.Error.Invalid, fn ->
        Ash.update!(task, %{title: "Unauthorized Update"},
          actor: other_user,
          tenant: other_workspace.id
        )
      end
    end

    test "raises error when updating with invalid title", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert_raise Ash.Error.Invalid, fn ->
        Ash.update!(task, %{title: nil}, actor: user, tenant: workspace.id)
      end
    end
  end

  describe "update_task/3 code interface" do
    test "updates a task using code interface", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Original Title #{System.unique_integer([:positive])}",
            description: "Original description",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      updated =
        Tasks.update_task!(
          task.id,
          %{
            title: "Updated Title #{System.unique_integer([:positive])}",
            description: "Updated description"
          },
          actor: user,
          tenant: workspace.id
        )

      assert updated.id == task.id
      assert updated.title != task.title
      assert updated.description == "Updated description"
      assert updated.task_state_id == task_state.id
    end

    test "can change task_state using code interface", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      # Create another task state
      new_state =
        Tasks.create_task_state!(%{
          name: "New State #{System.unique_integer([:positive])}",
          order: 2
        })

      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      updated =
        Tasks.update_task!(task.id, %{task_state_id: new_state.id},
          actor: user,
          tenant: workspace.id
        )

      assert updated.id == task.id
      assert updated.task_state_id == new_state.id
      assert updated.task_state_id != task_state.id
    end

    test "can update multiple fields at once", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      new_state =
        Tasks.create_task_state!(%{
          name: "Done State #{System.unique_integer([:positive])}",
          order: 3
        })

      task =
        Tasks.create_task!(
          %{
            title: "Original #{System.unique_integer([:positive])}",
            description: "Original desc",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      updated =
        Tasks.update_task!(
          task.id,
          %{
            title: "New Title",
            description: "New description",
            task_state_id: new_state.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert updated.title == "New Title"
      assert updated.description == "New description"
      assert updated.task_state_id == new_state.id
    end

    test "raises error when updating another user's task", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      other_user = generate(user())
      other_workspace = generate(workspace([], actor: other_user))

      task =
        Tasks.create_task!(
          %{
            title: "Protected Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # When using get_by, Ash returns Invalid (not found) to avoid leaking info about record existence
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.update_task!(task.id, %{title: "Unauthorized Update"},
          actor: other_user,
          tenant: other_workspace.id
        )
      end
    end

    test "raises error when updating with invalid title", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Valid Title #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.update_task!(task.id, %{title: nil}, actor: user, tenant: workspace.id)
      end
    end

    test "raises error when updating with non-existent task_state_id", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      fake_state_id = Ash.UUID.generate()

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.update_task!(task.id, %{task_state_id: fake_state_id},
          actor: user,
          tenant: workspace.id
        )
      end
    end

    test "raises error when updating non-existent task", %{user: user, workspace: workspace} do
      fake_task_id = Ash.UUID.generate()

      # get_by returns Invalid when record is not found
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.update_task!(fake_task_id, %{title: "Updated"}, actor: user, tenant: workspace.id)
      end
    end

    test "raises error when actor is not provided", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # With multitenancy, missing tenant is caught first, returning Invalid
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.update_task!(task.id, %{title: "Updated"})
      end
    end
  end

  describe "sub-tasks" do
    test "creates a sub-task with parent_task_id", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_task =
        Tasks.create_task!(
          %{
            title: "Sub Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert sub_task.parent_task_id == parent_task.id
      assert sub_task.workspace_id == parent_task.workspace_id
    end

    test "sub-task inherits workspace_id from parent task", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Create sub-task without explicitly setting workspace_id
      sub_task =
        Tasks.create_task!(
          %{
            title: "Sub Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert sub_task.workspace_id == workspace.id
    end

    test "can load parent_task relationship", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_task =
        Tasks.create_task!(
          %{
            title: "Sub Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: user,
          tenant: workspace.id
        )

      loaded_sub_task = Ash.load!(sub_task, :parent_task, actor: user, tenant: workspace.id)
      assert loaded_sub_task.parent_task.id == parent_task.id
    end

    test "can load sub_tasks relationship", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_task1 =
        Tasks.create_task!(
          %{
            title: "Sub Task 1 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_task2 =
        Tasks.create_task!(
          %{
            title: "Sub Task 2 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: user,
          tenant: workspace.id
        )

      loaded_parent = Ash.load!(parent_task, :sub_tasks, actor: user, tenant: workspace.id)
      sub_task_ids = Enum.map(loaded_parent.sub_tasks, & &1.id)

      assert sub_task1.id in sub_task_ids
      assert sub_task2.id in sub_task_ids
    end

    test "task without parent has nil parent_task_id", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Top Level Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert is_nil(task.parent_task_id)
    end

    test "raises error when parent_task_id does not exist", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      fake_parent_id = Ash.UUID.generate()

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task!(
          %{
            title: "Orphan Sub Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: fake_parent_id
          },
          actor: user,
          tenant: workspace.id
        )
      end
    end
  end

  describe "sub-tasks circular reference prevention" do
    test "sub-tasks can have their own independent task states", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      other_state =
        Tasks.create_task_state!(%{
          name: "Different State #{System.unique_integer([:positive])}",
          order: 5
        })

      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_task =
        Tasks.create_task!(
          %{
            title: "Sub Task #{System.unique_integer([:positive])}",
            task_state_id: other_state.id,
            parent_task_id: parent_task.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert sub_task.task_state_id == other_state.id
      assert parent_task.task_state_id == task_state.id
      assert sub_task.task_state_id != parent_task.task_state_id
    end

    test "allows valid parent-child relationship", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      parent =
        Tasks.create_task!(
          %{
            title: "Parent #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      child =
        Tasks.create_task!(
          %{
            title: "Child #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert child.parent_task_id == parent.id
    end

    test "allows multi-level hierarchy without cycles", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      grandparent =
        Tasks.create_task!(
          %{
            title: "Grandparent #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      parent =
        Tasks.create_task!(
          %{
            title: "Parent #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: grandparent.id
          },
          actor: user,
          tenant: workspace.id
        )

      child =
        Tasks.create_task!(
          %{
            title: "Child #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert grandparent.parent_task_id == nil
      assert parent.parent_task_id == grandparent.id
      assert child.parent_task_id == parent.id
    end
  end

  describe "destroy task" do
    test "destroys a task", %{user: user, workspace: workspace, task_state: task_state} do
      task =
        Tasks.create_task!(
          %{
            title: "To Delete #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert :ok = Ash.destroy!(task, actor: user, tenant: workspace.id)

      # Verify it's gone
      tasks = Tasks.list_tasks!(actor: user, tenant: workspace.id, query: [filter: [id: task.id]])
      assert tasks == []
    end

    test "raises error when destroying without authorization", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      # Create another user with their own workspace
      other_user = generate(user())
      other_workspace = generate(workspace([], actor: other_user))

      # Create task owned by the first user
      task =
        Tasks.create_task!(
          %{
            title: "Protected Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Try to destroy as the other user (with their tenant)
      # Gets Forbidden because other_user doesn't own the task (policy check on user_id)
      assert_raise Ash.Error.Forbidden, fn ->
        Ash.destroy!(task, actor: other_user, tenant: other_workspace.id)
      end
    end
  end

  describe "list_sub_tasks/2" do
    test "returns only sub-tasks of the specified parent", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_task1 =
        Tasks.create_task!(
          %{
            title: "Sub Task 1 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_task2 =
        Tasks.create_task!(
          %{
            title: "Sub Task 2 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Create another top-level task (should not be included)
      _other_task =
        Tasks.create_task!(
          %{
            title: "Other Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_tasks = Tasks.list_sub_tasks!(parent_task.id, actor: user, tenant: workspace.id)
      sub_task_ids = Enum.map(sub_tasks, & &1.id)

      assert length(sub_tasks) == 2
      assert sub_task1.id in sub_task_ids
      assert sub_task2.id in sub_task_ids
    end

    test "returns empty list when parent has no sub-tasks", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_tasks = Tasks.list_sub_tasks!(parent_task.id, actor: user, tenant: workspace.id)

      assert sub_tasks == []
    end
  end

  describe "list_top_level_tasks/1" do
    test "returns only tasks without parents", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      top_level_task1 =
        Tasks.create_task!(
          %{
            title: "Top Level 1 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      top_level_task2 =
        Tasks.create_task!(
          %{
            title: "Top Level 2 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Create a sub-task (should not be included)
      _sub_task =
        Tasks.create_task!(
          %{
            title: "Sub Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: top_level_task1.id
          },
          actor: user,
          tenant: workspace.id
        )

      top_level_tasks = Tasks.list_top_level_tasks!(actor: user, tenant: workspace.id)
      top_level_ids = Enum.map(top_level_tasks, & &1.id)

      assert top_level_task1.id in top_level_ids
      assert top_level_task2.id in top_level_ids

      # Verify the sub-task is not in the list
      refute Enum.any?(top_level_tasks, fn t -> t.parent_task_id != nil end)
    end

    test "returns empty list when no tasks exist", %{user: user, workspace: workspace} do
      top_level_tasks = Tasks.list_top_level_tasks!(actor: user, tenant: workspace.id)

      assert top_level_tasks == []
    end
  end

  describe "sub-task authorization" do
    test "workspace member can create sub-task on task in their workspace", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      # Create another user and add them as a workspace member
      other_user = create_user()
      Accounts.add_workspace_member!(other_user.id, workspace.id, actor: user)

      # First user creates a parent task
      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Second user (workspace member) can create a sub-task
      sub_task =
        Tasks.create_task!(
          %{
            title: "Sub Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: other_user,
          tenant: workspace.id
        )

      assert sub_task.parent_task_id == parent_task.id
      assert sub_task.workspace_id == workspace.id
      assert sub_task.user_id == other_user.id
    end

    test "non-member cannot create sub-task on task in workspace they don't belong to", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      # Create another user with their own workspace (not a member of first workspace)
      other_user = generate(user())
      other_workspace = generate(workspace([], actor: other_user))

      # First user creates a parent task in their workspace
      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Second user (not a member) cannot create a sub-task
      # They can't even see the parent task due to tenant isolation
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task!(
          %{
            title: "Unauthorized Sub Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: other_user,
          tenant: other_workspace.id
        )
      end
    end

    test "user cannot create sub-task with parent from different workspace", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      # Create a second workspace for the same user
      second_workspace = generate(workspace([], actor: user))

      # Create parent task in first workspace
      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Try to create sub-task in second workspace with parent from first workspace
      # This should fail because parent doesn't exist in the tenant
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task!(
          %{
            title: "Cross-workspace Sub Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: user,
          tenant: second_workspace.id
        )
      end
    end
  end

  describe "human_id" do
    test "task is assigned a human_id on creation", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert task.human_id != nil
      assert is_binary(task.human_id)
    end

    test "human_id follows PREFIX-NUMBER format", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Human ID should match PREFIX-NUMBER format (1-3 uppercase letters, hyphen, number)
      assert Regex.match?(~r/^[A-Z]{1,3}-\d+$/, task.human_id)
    end

    test "human_id uses workspace prefix", %{
      user: user,
      task_state: task_state
    } do
      # Create workspace with a known name to get predictable prefix
      workspace =
        Accounts.create_workspace!("Test Project", actor: user)

      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # "Test Project" has uppercase T and P, so prefix should be "TP"
      assert String.starts_with?(task.human_id, "TP-")
    end

    test "human_ids increment sequentially within workspace", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task1 =
        Tasks.create_task!(
          %{
            title: "Task 1 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      task2 =
        Tasks.create_task!(
          %{
            title: "Task 2 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      task3 =
        Tasks.create_task!(
          %{
            title: "Task 3 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Extract numbers from human_ids
      [_, num1] = String.split(task1.human_id, "-")
      [_, num2] = String.split(task2.human_id, "-")
      [_, num3] = String.split(task3.human_id, "-")

      num1 = String.to_integer(num1)
      num2 = String.to_integer(num2)
      num3 = String.to_integer(num3)

      assert num2 == num1 + 1
      assert num3 == num2 + 1
    end

    test "different workspaces have independent human_id sequences", %{
      user: user,
      task_state: task_state
    } do
      workspace1 = Accounts.create_workspace!("Workspace One", actor: user)
      workspace2 = Accounts.create_workspace!("Workspace Two", actor: user)

      task1 =
        Tasks.create_task!(
          %{
            title: "Task in WS1 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace1.id
          },
          actor: user,
          tenant: workspace1.id
        )

      task2 =
        Tasks.create_task!(
          %{
            title: "Task in WS2 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace2.id
          },
          actor: user,
          tenant: workspace2.id
        )

      # Both should be the first task in their workspace
      assert String.ends_with?(task1.human_id, "-1")
      assert String.ends_with?(task2.human_id, "-1")

      # But they should have different prefixes
      [prefix1, _] = String.split(task1.human_id, "-")
      [prefix2, _] = String.split(task2.human_id, "-")
      assert prefix1 == "WO"
      assert prefix2 == "WT"
    end

    test "sub-tasks get their own human_id", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      parent_task =
        Tasks.create_task!(
          %{
            title: "Parent Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      sub_task =
        Tasks.create_task!(
          %{
            title: "Sub Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            parent_task_id: parent_task.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert sub_task.human_id != nil
      assert sub_task.human_id != parent_task.human_id

      # Sub-task should have the next sequential number
      [_, parent_num] = String.split(parent_task.human_id, "-")
      [_, sub_num] = String.split(sub_task.human_id, "-")
      assert String.to_integer(sub_num) == String.to_integer(parent_num) + 1
    end

    test "human_id cannot be manually set on creation", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      # Attempting to pass human_id should raise an error since it's not writable
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id,
            human_id: "CUSTOM-999"
          },
          actor: user,
          tenant: workspace.id
        )
      end
    end
  end

  describe "get_task_by_human_id/2" do
    test "retrieves task by human_id", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Find Me #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      found_task = Tasks.get_task_by_human_id!(task.human_id, actor: user, tenant: workspace.id)

      assert found_task.id == task.id
      assert found_task.title == task.title
      assert found_task.human_id == task.human_id
    end

    test "raises error for non-existent human_id", %{user: user, workspace: workspace} do
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.get_task_by_human_id!("FAKE-9999", actor: user, tenant: workspace.id)
      end
    end

    test "cannot retrieve task from different workspace by human_id", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      other_user = generate(user())
      other_workspace = generate(workspace([], actor: other_user))

      task =
        Tasks.create_task!(
          %{
            title: "Secret Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      # Try to retrieve from different workspace's tenant
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.get_task_by_human_id!(task.human_id, actor: other_user, tenant: other_workspace.id)
      end
    end
  end
end
