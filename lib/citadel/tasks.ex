defmodule Citadel.Tasks do
  @moduledoc """
  The Tasks domain, managing task items and their states.
  """
  use Ash.Domain,
    otp_app: :citadel

  resources do
    resource Citadel.Tasks.TaskState do
      define :create_task_state, action: :create
      define :list_task_states, action: :read
    end

    resource Citadel.Tasks.Task do
      define :create_task, action: :create
      define :list_tasks, action: :read
      define :get_task, action: :read, get_by: [:id]
      define :update_task, action: :update, get_by: [:id]
    end
  end
end
