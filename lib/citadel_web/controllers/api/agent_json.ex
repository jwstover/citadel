defmodule CitadelWeb.Api.AgentJSON do
  def task(%{task: task}) do
    %{
      data: %{
        id: task.id,
        human_id: task.human_id,
        title: task.title,
        description: task.description,
        priority: task.priority,
        due_date: task.due_date,
        agent_eligible: task.agent_eligible,
        task_state: %{
          id: task.task_state.id,
          name: task.task_state.name
        },
        inserted_at: task.inserted_at,
        updated_at: task.updated_at
      }
    }
  end

  def agent_run(%{agent_run: agent_run}) do
    %{
      data: %{
        id: agent_run.id,
        task_id: agent_run.task_id,
        status: agent_run.status,
        diff: agent_run.diff,
        test_output: agent_run.test_output,
        logs: agent_run.logs,
        error_message: agent_run.error_message,
        started_at: agent_run.started_at,
        completed_at: agent_run.completed_at,
        inserted_at: agent_run.inserted_at,
        updated_at: agent_run.updated_at
      }
    }
  end

  def error(%{error: error}) do
    %{
      errors:
        Enum.map(Ash.Error.to_ash_error(error).errors, fn e ->
          %{detail: Exception.message(e)}
        end)
    }
  end
end
