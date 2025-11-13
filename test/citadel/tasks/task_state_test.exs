defmodule Citadel.Tasks.TaskStateTest do
  use Citadel.DataCase, async: true

  alias Citadel.Tasks

  describe "create_task_state/2" do
    test "creates a task state with valid attributes" do
      attrs = %{
        name: "Task #{System.unique_integer([:positive])}",
        description: "A task state",
        order: 1
      }

      assert task_state = Tasks.create_task_state!(attrs)
      assert task_state.name == attrs.name
      assert task_state.description == attrs.description
      assert task_state.order == attrs.order
      assert task_state.is_complete == false
    end

    test "creates a task state with is_complete set to true" do
      attrs = %{
        name: "Completed #{System.unique_integer([:positive])}",
        description: "A completed state",
        order: 2,
        is_complete: true
      }

      assert task_state = Tasks.create_task_state!(attrs)
      assert task_state.is_complete == true
    end

    test "creates a task state without optional description" do
      attrs = %{
        name: "Minimal #{System.unique_integer([:positive])}",
        order: 3
      }

      assert task_state = Tasks.create_task_state!(attrs)
      assert task_state.name == attrs.name
      assert is_nil(task_state.description)
      assert task_state.order == attrs.order
    end

    test "raises error when name is missing" do
      attrs = %{
        order: 1
      }

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task_state!(attrs)
      end
    end

    test "raises error when order is missing" do
      attrs = %{
        name: "Missing Order #{System.unique_integer([:positive])}"
      }

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_task_state!(attrs)
      end
    end
  end

  describe "list_task_states/1" do
    test "returns all task states" do
      # Create multiple task states
      _state1 =
        Tasks.create_task_state!(%{
          name: "State 1 #{System.unique_integer([:positive])}",
          order: 1
        })

      _state2 =
        Tasks.create_task_state!(%{
          name: "State 2 #{System.unique_integer([:positive])}",
          order: 2
        })

      states = Tasks.list_task_states!()
      assert length(states) >= 2
    end

    test "returns empty list when no task states exist" do
      states = Tasks.list_task_states!()
      assert is_list(states)
    end

    test "can filter task states by is_complete" do
      _incomplete =
        Tasks.create_task_state!(%{
          name: "Incomplete #{System.unique_integer([:positive])}",
          order: 1,
          is_complete: false
        })

      complete =
        Tasks.create_task_state!(%{
          name: "Complete #{System.unique_integer([:positive])}",
          order: 2,
          is_complete: true
        })

      states = Tasks.list_task_states!(query: [filter: [is_complete: true]])
      assert complete.id in Enum.map(states, & &1.id)
    end

    test "can sort task states by order" do
      state1 =
        Tasks.create_task_state!(%{
          name: "State 1 #{System.unique_integer([:positive])}",
          order: 3
        })

      state2 =
        Tasks.create_task_state!(%{
          name: "State 2 #{System.unique_integer([:positive])}",
          order: 1
        })

      state3 =
        Tasks.create_task_state!(%{
          name: "State 3 #{System.unique_integer([:positive])}",
          order: 2
        })

      states =
        Tasks.list_task_states!(
          query: [
            filter: [id: [in: [state1.id, state2.id, state3.id]]],
            sort: [order: :asc]
          ]
        )

      assert length(states) == 3
      assert hd(states).id == state2.id
      assert List.last(states).id == state1.id
    end
  end

  describe "update task state" do
    test "updates a task state with valid attributes" do
      task_state =
        Tasks.create_task_state!(%{
          name: "Original #{System.unique_integer([:positive])}",
          order: 1
        })

      updated =
        Ash.update!(task_state, %{
          name: "Updated #{System.unique_integer([:positive])}",
          order: 2
        })

      assert updated.id == task_state.id
      assert updated.name != task_state.name
      assert updated.order == 2
    end

    test "updates is_complete flag" do
      task_state =
        Tasks.create_task_state!(%{
          name: "State #{System.unique_integer([:positive])}",
          order: 1,
          is_complete: false
        })

      updated = Ash.update!(task_state, %{is_complete: true})

      assert updated.is_complete == true
    end

    test "raises error when updating with invalid name" do
      task_state =
        Tasks.create_task_state!(%{
          name: "State #{System.unique_integer([:positive])}",
          order: 1
        })

      assert_raise Ash.Error.Invalid, fn ->
        Ash.update!(task_state, %{name: nil})
      end
    end
  end

  describe "destroy task state" do
    test "destroys a task state" do
      task_state =
        Tasks.create_task_state!(%{
          name: "To Delete #{System.unique_integer([:positive])}",
          order: 1
        })

      assert :ok = Ash.destroy!(task_state)

      # Verify it's gone
      states = Tasks.list_task_states!(query: [filter: [id: task_state.id]])
      assert states == []
    end
  end
end
