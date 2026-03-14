defmodule CitadelWeb.Api.AgentJSON do
  def claim(%{agent_run: agent_run}) do
    task = agent_run.task

    %{
      data: %{
        task: %{
          id: task.id,
          human_id: task.human_id,
          title: task.title,
          description: task.description,
          priority: task.priority,
          due_date: task.due_date,
          agent_eligible: task.agent_eligible,
          parent_task_id: task.parent_task_id,
          parent_human_id: if(task.parent_task, do: task.parent_task.human_id),
          task_state: %{
            id: task.task_state.id,
            name: task.task_state.name
          },
          inserted_at: task.inserted_at,
          updated_at: task.updated_at
        },
        agent_run: %{
          id: agent_run.id,
          task_id: agent_run.task_id,
          status: agent_run.status,
          started_at: agent_run.started_at,
          completed_at: agent_run.completed_at,
          inserted_at: agent_run.inserted_at,
          updated_at: agent_run.updated_at
        }
      }
    }
  end

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
        parent_task_id: task.parent_task_id,
        parent_human_id: if(task.parent_task, do: task.parent_task.human_id),
        task_state: %{
          id: task.task_state.id,
          name: task.task_state.name
        },
        forge_pr: task.forge_pr,
        inserted_at: task.inserted_at,
        updated_at: task.updated_at
      }
    }
  end

  def task_states(%{task_states: task_states}) do
    %{
      data:
        Enum.map(task_states, fn state ->
          %{
            id: state.id,
            name: state.name,
            order: state.order,
            is_complete: state.is_complete
          }
        end)
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

  def agent_run_event(%{event: event}) do
    %{
      data: %{
        id: event.id,
        agent_run_id: event.agent_run_id,
        event_type: event.event_type,
        message: event.message,
        metadata: event.metadata,
        inserted_at: event.inserted_at,
        updated_at: event.updated_at
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
