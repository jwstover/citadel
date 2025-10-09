defmodule Citadel.Todos.TodoTest do
  use Citadel.DataCase, async: true

  alias Citadel.Todos

  setup do
    # Create a user for testing
    user = create_user()

    # Create a todo state for testing
    todo_state =
      Todos.create_todo_state!(%{
        name: "Todo State #{System.unique_integer([:positive])}",
        order: 1
      })

    {:ok, user: user, todo_state: todo_state}
  end

  describe "create_todo/2" do
    test "creates a todo with valid attributes", %{user: user, todo_state: todo_state} do
      attrs = %{
        title: "Test Todo #{System.unique_integer([:positive])}",
        description: "A test todo",
        todo_state_id: todo_state.id
      }

      assert todo = Todos.create_todo!(attrs, actor: user)
      assert todo.title == attrs.title
      assert todo.description == attrs.description
      assert todo.todo_state_id == todo_state.id
      assert todo.user_id == user.id
    end

    test "creates a todo without optional description", %{user: user, todo_state: todo_state} do
      attrs = %{
        title: "Minimal Todo #{System.unique_integer([:positive])}",
        todo_state_id: todo_state.id
      }

      assert todo = Todos.create_todo!(attrs, actor: user)
      assert todo.title == attrs.title
      assert is_nil(todo.description)
    end

    test "raises error when title is missing", %{user: user, todo_state: todo_state} do
      attrs = %{
        todo_state_id: todo_state.id
      }

      assert_raise Ash.Error.Invalid, fn ->
        Todos.create_todo!(attrs, actor: user)
      end
    end

    test "raises error when todo_state_id is missing", %{user: user} do
      attrs = %{
        title: "Missing State #{System.unique_integer([:positive])}"
      }

      assert_raise Ash.Error.Invalid, fn ->
        Todos.create_todo!(attrs, actor: user)
      end
    end

    test "raises error when actor is missing", %{todo_state: todo_state} do
      attrs = %{
        title: "Missing User #{System.unique_integer([:positive])}",
        todo_state_id: todo_state.id
      }

      assert_raise Ash.Error.Invalid, fn ->
        Todos.create_todo!(attrs)
      end
    end
  end

  describe "list_todos/1" do
    test "returns todos for the actor user", %{user: user, todo_state: todo_state} do
      # Create todos for this user
      todo1 =
        Todos.create_todo!(
          %{
            title: "Todo 1 #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      todo2 =
        Todos.create_todo!(
          %{
            title: "Todo 2 #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      # List todos as this user
      todos = Todos.list_todos!(actor: user)
      todo_ids = Enum.map(todos, & &1.id)

      assert todo1.id in todo_ids
      assert todo2.id in todo_ids
    end

    test "does not return todos from other users", %{user: user, todo_state: todo_state} do
      # Create another user
      other_user = create_user()

      # Create todo for the other user
      other_todo =
        Todos.create_todo!(
          %{
            title: "Other User Todo #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: other_user
        )

      # Create todo for the first user
      user_todo =
        Todos.create_todo!(
          %{
            title: "User Todo #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      # List todos as the first user
      todos = Todos.list_todos!(actor: user)
      todo_ids = Enum.map(todos, & &1.id)

      assert user_todo.id in todo_ids
      refute other_todo.id in todo_ids
    end

    test "returns empty list when user has no todos", %{user: user} do
      todos = Todos.list_todos!(actor: user)
      assert todos == []
    end

    test "can filter todos by todo_state", %{user: user, todo_state: todo_state} do
      # Create another todo state
      other_state =
        Todos.create_todo_state!(%{
          name: "Other State #{System.unique_integer([:positive])}",
          order: 2
        })

      # Create todos with different states
      todo1 =
        Todos.create_todo!(
          %{
            title: "Todo State 1 #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      _todo2 =
        Todos.create_todo!(
          %{
            title: "Todo State 2 #{System.unique_integer([:positive])}",
            todo_state_id: other_state.id
          },
          actor: user
        )

      # Filter by first todo state
      todos =
        Todos.list_todos!(
          actor: user,
          query: [filter: [todo_state_id: todo_state.id]]
        )

      assert length(todos) == 1
      assert hd(todos).id == todo1.id
    end

    test "can load relationships", %{user: user, todo_state: todo_state} do
      todo =
        Todos.create_todo!(
          %{
            title: "Todo with Relations #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      todos =
        Todos.list_todos!(
          actor: user,
          query: [filter: [id: todo.id]],
          load: [:todo_state, :user]
        )

      assert length(todos) == 1
      loaded_todo = hd(todos)
      assert loaded_todo.todo_state.id == todo_state.id
      assert loaded_todo.user.id == user.id
    end
  end

  describe "update todo" do
    test "updates a todo with valid attributes", %{user: user, todo_state: todo_state} do
      todo =
        Todos.create_todo!(
          %{
            title: "Original Title #{System.unique_integer([:positive])}",
            description: "Original description",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      updated =
        Ash.update!(
          todo,
          %{
            title: "Updated Title #{System.unique_integer([:positive])}",
            description: "Updated description"
          },
          actor: user
        )

      assert updated.id == todo.id
      assert updated.title != todo.title
      assert updated.description == "Updated description"
    end

    test "can change todo_state", %{user: user, todo_state: todo_state} do
      # Create another todo state
      new_state =
        Todos.create_todo_state!(%{
          name: "New State #{System.unique_integer([:positive])}",
          order: 2
        })

      todo =
        Todos.create_todo!(
          %{
            title: "Todo #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      updated = Ash.update!(todo, %{todo_state_id: new_state.id}, actor: user)

      assert updated.todo_state_id == new_state.id
    end

    test "raises error when updating without authorization", %{user: user, todo_state: todo_state} do
      # Create another user
      other_user = create_user()

      # Create todo owned by the first user
      todo =
        Todos.create_todo!(
          %{
            title: "Protected Todo #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      # Try to update as the other user
      assert_raise Ash.Error.Forbidden, fn ->
        Ash.update!(todo, %{title: "Unauthorized Update"}, actor: other_user)
      end
    end

    test "raises error when updating with invalid title", %{user: user, todo_state: todo_state} do
      todo =
        Todos.create_todo!(
          %{
            title: "Todo #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      assert_raise Ash.Error.Invalid, fn ->
        Ash.update!(todo, %{title: nil}, actor: user)
      end
    end
  end

  describe "destroy todo" do
    test "destroys a todo", %{user: user, todo_state: todo_state} do
      todo =
        Todos.create_todo!(
          %{
            title: "To Delete #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      assert :ok = Ash.destroy!(todo, actor: user)

      # Verify it's gone
      todos = Todos.list_todos!(actor: user, query: [filter: [id: todo.id]])
      assert todos == []
    end

    test "raises error when destroying without authorization", %{
      user: user,
      todo_state: todo_state
    } do
      # Create another user
      other_user = create_user()

      # Create todo owned by the first user
      todo =
        Todos.create_todo!(
          %{
            title: "Protected Todo #{System.unique_integer([:positive])}",
            todo_state_id: todo_state.id
          },
          actor: user
        )

      # Try to destroy as the other user
      assert_raise Ash.Error.Forbidden, fn ->
        Ash.destroy!(todo, actor: other_user)
      end
    end
  end
end
