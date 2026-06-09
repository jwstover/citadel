defmodule CitadelAgent.Runners do
  @moduledoc """
  Helper functions for querying the RunnerRegistry to determine the status
  of active TaskRunner processes.
  """

  @registry CitadelAgent.RunnerRegistry

  def get_status do
    case Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) do
      [] -> {"idle", nil}
      [task_id | _] -> {"working", task_id}
    end
  end

  def has_active_runner? do
    Registry.count(@registry) > 0
  end

  def lookup(task_id) do
    case Registry.lookup(@registry, task_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end
end
