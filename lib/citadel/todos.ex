defmodule Citadel.Todos do
  use Ash.Domain,
    otp_app: :citadel

  resources do
    resource Citadel.Todos.TodoState do
      define :create_todo_state, action: :create
      define :list_todo_states, action: :read
    end
  end
end
