defmodule Citadel.Tasks.TaskTest do
  use Citadel.DataCase, async: true

  alias Citadel.Tasks

  setup do
    # Create a user for testing
    user = create_user()

    # Create a task state for testing
    task_state =
      Tasks.create_task_state!(%{
        name: "Task State #{System.unique_integer([:positive])}",
        order: 1
      })

    {:ok, user: user, task_state: task_state}
  end

  describe "create_task/2" do
    test "creates a task with valid attributes", %{user: user, task_state: task_state} do
      attrs = %{
        title: "Test Task #{System.unique_integer([:positive])}",
        description: "A test task",
        task_state_id: task_state.id
      }

      assert task = Tasks.create_task!(attrs, actor: user)
      assert task.title == attrs.title
      assert task.description == attrs.description
      assert task.task_state_id == task_state.id
      assert task.user_id == user.id
    end

    test "creates a task without optional description", %{user: user, task_state: task_state} do
      attrs = %{
        title: "Minimal Task #{System.unique_integer([:positive])}",
        task_state_id: task_state.id
      }

      assert task = Tasks.create_task!(attrs, actor: user)
      assert task.title == attrs.title
      assert is_nil(task.description)
    end

    test "raises error when title is missing", %{user: user, task_state: task_state} do
      attrs = %{
        task_state_id: task_state.id
      }

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task!(attrs, actor: user)
      end
    end

    test "sets default task_state_id to the state with lowest order when not provided", %{
      user: user
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
        title: "Task Without State #{System.unique_integer([:positive])}"
      }

      task = Tasks.create_task!(attrs, actor: user)

      # Should default to the task_state with order: 0
      assert task.task_state_id == lowest_order_state.id
    end

    test "raises error when actor is missing", %{task_state: task_state} do
      attrs = %{
        title: "Missing User #{System.unique_integer([:positive])}",
        task_state_id: task_state.id
      }

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task!(attrs)
      end
    end
  end

  describe "list_tasks/1" do
    test "returns tasks for the actor user", %{user: user, task_state: task_state} do
      # Create tasks for this user
      task1 =
        Tasks.create_task!(
          %{
            title: "Task 1 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      task2 =
        Tasks.create_task!(
          %{
            title: "Task 2 #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      # List tasks as this user
      tasks = Tasks.list_tasks!(actor: user)
      task_ids = Enum.map(tasks, & &1.id)

      assert task1.id in task_ids
      assert task2.id in task_ids
    end

    test "does not return tasks from other users", %{user: user, task_state: task_state} do
      # Create another user
      other_user = create_user()

      # Create task for the other user
      other_task =
        Tasks.create_task!(
          %{
            title: "Other User Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: other_user
        )

      # Create task for the first user
      user_task =
        Tasks.create_task!(
          %{
            title: "User Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      # List tasks as the first user
      tasks = Tasks.list_tasks!(actor: user)
      task_ids = Enum.map(tasks, & &1.id)

      assert user_task.id in task_ids
      refute other_task.id in task_ids
    end

    test "returns empty list when user has no tasks", %{user: user} do
      tasks = Tasks.list_tasks!(actor: user)
      assert tasks == []
    end

    test "can filter tasks by task_state", %{user: user, task_state: task_state} do
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
            task_state_id: task_state.id
          },
          actor: user
        )

      _task2 =
        Tasks.create_task!(
          %{
            title: "Task State 2 #{System.unique_integer([:positive])}",
            task_state_id: other_state.id
          },
          actor: user
        )

      # Filter by first task state
      tasks =
        Tasks.list_tasks!(
          actor: user,
          query: [filter: [task_state_id: task_state.id]]
        )

      assert length(tasks) == 1
      assert hd(tasks).id == task1.id
    end

    test "can load relationships", %{user: user, task_state: task_state} do
      task =
        Tasks.create_task!(
          %{
            title: "Task with Relations #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      tasks =
        Tasks.list_tasks!(
          actor: user,
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
    test "updates a task with valid attributes", %{user: user, task_state: task_state} do
      task =
        Tasks.create_task!(
          %{
            title: "Original Title #{System.unique_integer([:positive])}",
            description: "Original description",
            task_state_id: task_state.id
          },
          actor: user
        )

      updated =
        Ash.update!(
          task,
          %{
            title: "Updated Title #{System.unique_integer([:positive])}",
            description: "Updated description"
          },
          actor: user
        )

      assert updated.id == task.id
      assert updated.title != task.title
      assert updated.description == "Updated description"
    end

    test "can change task_state", %{user: user, task_state: task_state} do
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
            task_state_id: task_state.id
          },
          actor: user
        )

      updated = Ash.update!(task, %{task_state_id: new_state.id}, actor: user)

      assert updated.task_state_id == new_state.id
    end

    test "raises error when updating without authorization", %{user: user, task_state: task_state} do
      # Create another user
      other_user = create_user()

      # Create task owned by the first user
      task =
        Tasks.create_task!(
          %{
            title: "Protected Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      # Try to update as the other user
      assert_raise Ash.Error.Forbidden, fn ->
        Ash.update!(task, %{title: "Unauthorized Update"}, actor: other_user)
      end
    end

    test "raises error when updating with invalid title", %{user: user, task_state: task_state} do
      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      assert_raise Ash.Error.Invalid, fn ->
        Ash.update!(task, %{title: nil}, actor: user)
      end
    end
  end

  describe "update_task/3 code interface" do
    test "updates a task using code interface", %{user: user, task_state: task_state} do
      task =
        Tasks.create_task!(
          %{
            title: "Original Title #{System.unique_integer([:positive])}",
            description: "Original description",
            task_state_id: task_state.id
          },
          actor: user
        )

      updated =
        Tasks.update_task!(
          task.id,
          %{
            title: "Updated Title #{System.unique_integer([:positive])}",
            description: "Updated description"
          },
          actor: user
        )

      assert updated.id == task.id
      assert updated.title != task.title
      assert updated.description == "Updated description"
      assert updated.task_state_id == task_state.id
    end

    test "can change task_state using code interface", %{user: user, task_state: task_state} do
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
            task_state_id: task_state.id
          },
          actor: user
        )

      updated = Tasks.update_task!(task.id, %{task_state_id: new_state.id}, actor: user)

      assert updated.id == task.id
      assert updated.task_state_id == new_state.id
      assert updated.task_state_id != task_state.id
    end

    test "can update multiple fields at once", %{user: user, task_state: task_state} do
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
            task_state_id: task_state.id
          },
          actor: user
        )

      updated =
        Tasks.update_task!(
          task.id,
          %{
            title: "New Title",
            description: "New description",
            task_state_id: new_state.id
          },
          actor: user
        )

      assert updated.title == "New Title"
      assert updated.description == "New description"
      assert updated.task_state_id == new_state.id
    end

    test "raises error when updating another user's task", %{user: user, task_state: task_state} do
      other_user = create_user()

      task =
        Tasks.create_task!(
          %{
            title: "Protected Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      # When using get_by, Ash returns Invalid (not found) to avoid leaking info about record existence
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.update_task!(task.id, %{title: "Unauthorized Update"}, actor: other_user)
      end
    end

    test "raises error when updating with invalid title", %{user: user, task_state: task_state} do
      task =
        Tasks.create_task!(
          %{
            title: "Valid Title #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.update_task!(task.id, %{title: nil}, actor: user)
      end
    end

    test "raises error when updating with non-existent task_state_id", %{
      user: user,
      task_state: task_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      fake_state_id = Ash.UUID.generate()

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.update_task!(task.id, %{task_state_id: fake_state_id}, actor: user)
      end
    end

    test "raises error when updating non-existent task", %{user: user} do
      fake_task_id = Ash.UUID.generate()

      # get_by returns Invalid when record is not found
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.update_task!(fake_task_id, %{title: "Updated"}, actor: user)
      end
    end

    test "raises error when actor is not provided", %{user: user, task_state: task_state} do
      task =
        Tasks.create_task!(
          %{
            title: "Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      assert_raise Ash.Error.Forbidden, fn ->
        Tasks.update_task!(task.id, %{title: "Updated"})
      end
    end
  end

  describe "destroy task" do
    test "destroys a task", %{user: user, task_state: task_state} do
      task =
        Tasks.create_task!(
          %{
            title: "To Delete #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      assert :ok = Ash.destroy!(task, actor: user)

      # Verify it's gone
      tasks = Tasks.list_tasks!(actor: user, query: [filter: [id: task.id]])
      assert tasks == []
    end

    test "raises error when destroying without authorization", %{
      user: user,
      task_state: task_state
    } do
      # Create another user
      other_user = create_user()

      # Create task owned by the first user
      task =
        Tasks.create_task!(
          %{
            title: "Protected Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id
          },
          actor: user
        )

      # Try to destroy as the other user
      assert_raise Ash.Error.Forbidden, fn ->
        Ash.destroy!(task, actor: other_user)
      end
    end
  end
end
