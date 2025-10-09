defmodule Citadel.Todos do
  @moduledoc """
  The Todos domain, managing todo items and their states.
  """
  use Ash.Domain,
    otp_app: :citadel

  resources do
    resource Citadel.Todos.TodoState do
      define :create_todo_state, action: :create
      define :list_todo_states, action: :read
    end

    resource Citadel.Todos.Todo do
      define :create_todo, action: :create
      define :list_todos, action: :read
      define :update_todo, action: :update, get_by: [:id]
    end
  end
end
