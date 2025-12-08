defmodule Citadel.Tasks do
  @moduledoc """
  The Tasks domain, managing task items and their states.
  """
  use Ash.Domain,
    otp_app: :citadel,
    extensions: [AshAi, AshPhoenix]

  tools do
    tool :list_tasks, Citadel.Tasks.Task, :read do
      description "Lists all tasks for the current user"
      load [:task_state]
    end

    tool :create_task, Citadel.Tasks.Task, :create do
      description "Creates a new task with a title, optional description, and task state. To create a sub-task, provide a parent_task_id."
    end

    tool :update_task, Citadel.Tasks.Task, :update do
      description "Updates an existing task's title, description, or state"
    end

    tool :list_task_states, Citadel.Tasks.TaskState, :read do
      description "Lists all available task states (e.g., 'To Do', 'In Progress', 'Done')"
    end
  end

  resources do
    resource Citadel.Tasks.WorkspaceTaskCounter do
      define :create_workspace_task_counter, action: :create
      define :increment_task_counter, action: :increment
      define :get_task_counter, action: :read, get_by: [:workspace_id]
    end

    resource Citadel.Tasks.TaskState do
      define :create_task_state, action: :create
      define :list_task_states, action: :read
    end

    resource Citadel.Tasks.Task do
      define :create_task, action: :create
      define :list_tasks, action: :read
      define :list_sub_tasks, action: :list_sub_tasks, args: [:parent_task_id]
      define :list_top_level_tasks, action: :list_top_level
      define :get_task, action: :read, get_by: [:id]
      define :get_task_by_human_id, action: :read, get_by: [:human_id]
      define :update_task, action: :update, get_by: [:id]
      define :parse_task_from_text, action: :parse_task_from_text, args: [:text]
    end
  end
end
