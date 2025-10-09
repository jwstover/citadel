defmodule Citadel.Todos.TodoStateTest do
  use Citadel.DataCase, async: true

  alias Citadel.Todos

  describe "create_todo_state/2" do
    test "creates a todo state with valid attributes" do
      attrs = %{
        name: "Todo #{System.unique_integer([:positive])}",
        description: "A todo state",
        order: 1
      }

      assert todo_state = Todos.create_todo_state!(attrs)
      assert todo_state.name == attrs.name
      assert todo_state.description == attrs.description
      assert todo_state.order == attrs.order
      assert todo_state.is_complete == false
    end

    test "creates a todo state with is_complete set to true" do
      attrs = %{
        name: "Completed #{System.unique_integer([:positive])}",
        description: "A completed state",
        order: 2,
        is_complete: true
      }

      assert todo_state = Todos.create_todo_state!(attrs)
      assert todo_state.is_complete == true
    end

    test "creates a todo state without optional description" do
      attrs = %{
        name: "Minimal #{System.unique_integer([:positive])}",
        order: 3
      }

      assert todo_state = Todos.create_todo_state!(attrs)
      assert todo_state.name == attrs.name
      assert is_nil(todo_state.description)
      assert todo_state.order == attrs.order
    end

    test "raises error when name is missing" do
      attrs = %{
        order: 1
      }

      assert_raise Ash.Error.Invalid, fn ->
        Todos.create_todo_state!(attrs)
      end
    end

    test "raises error when order is missing" do
      attrs = %{
        name: "Missing Order #{System.unique_integer([:positive])}"
      }

      assert_raise Ash.Error.Invalid, fn ->
        Todos.create_todo_state!(attrs)
      end
    end
  end

  describe "list_todo_states/1" do
    test "returns all todo states" do
      # Create multiple todo states
      _state1 =
        Todos.create_todo_state!(%{
          name: "State 1 #{System.unique_integer([:positive])}",
          order: 1
        })

      _state2 =
        Todos.create_todo_state!(%{
          name: "State 2 #{System.unique_integer([:positive])}",
          order: 2
        })

      states = Todos.list_todo_states!()
      assert length(states) >= 2
    end

    test "returns empty list when no todo states exist" do
      states = Todos.list_todo_states!()
      assert is_list(states)
    end

    test "can filter todo states by is_complete" do
      _incomplete =
        Todos.create_todo_state!(%{
          name: "Incomplete #{System.unique_integer([:positive])}",
          order: 1,
          is_complete: false
        })

      complete =
        Todos.create_todo_state!(%{
          name: "Complete #{System.unique_integer([:positive])}",
          order: 2,
          is_complete: true
        })

      states = Todos.list_todo_states!(query: [filter: [is_complete: true]])
      assert complete.id in Enum.map(states, & &1.id)
    end

    test "can sort todo states by order" do
      state1 =
        Todos.create_todo_state!(%{
          name: "State 1 #{System.unique_integer([:positive])}",
          order: 3
        })

      state2 =
        Todos.create_todo_state!(%{
          name: "State 2 #{System.unique_integer([:positive])}",
          order: 1
        })

      state3 =
        Todos.create_todo_state!(%{
          name: "State 3 #{System.unique_integer([:positive])}",
          order: 2
        })

      states =
        Todos.list_todo_states!(
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

  describe "update todo state" do
    test "updates a todo state with valid attributes" do
      todo_state =
        Todos.create_todo_state!(%{
          name: "Original #{System.unique_integer([:positive])}",
          order: 1
        })

      updated =
        Ash.update!(todo_state, %{
          name: "Updated #{System.unique_integer([:positive])}",
          order: 2
        })

      assert updated.id == todo_state.id
      assert updated.name != todo_state.name
      assert updated.order == 2
    end

    test "updates is_complete flag" do
      todo_state =
        Todos.create_todo_state!(%{
          name: "State #{System.unique_integer([:positive])}",
          order: 1,
          is_complete: false
        })

      updated = Ash.update!(todo_state, %{is_complete: true})

      assert updated.is_complete == true
    end

    test "raises error when updating with invalid name" do
      todo_state =
        Todos.create_todo_state!(%{
          name: "State #{System.unique_integer([:positive])}",
          order: 1
        })

      assert_raise Ash.Error.Invalid, fn ->
        Ash.update!(todo_state, %{name: nil})
      end
    end
  end

  describe "destroy todo state" do
    test "destroys a todo state" do
      todo_state =
        Todos.create_todo_state!(%{
          name: "To Delete #{System.unique_integer([:positive])}",
          order: 1
        })

      assert :ok = Ash.destroy!(todo_state)

      # Verify it's gone
      states = Todos.list_todo_states!(query: [filter: [id: todo_state.id]])
      assert states == []
    end
  end
end
