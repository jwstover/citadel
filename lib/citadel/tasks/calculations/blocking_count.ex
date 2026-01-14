defmodule Citadel.Tasks.Calculations.BlockingCount do
  @moduledoc """
  Calculates the count of incomplete dependencies blocking a task.

  Returns:
  - Integer count of dependencies with incomplete task_states
  - 0 if all dependencies are complete or there are no dependencies
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [dependencies: [task_state: [:is_complete]]]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.dependencies do
        %Ash.NotLoaded{} -> 0
        dependencies -> Enum.count(dependencies, &dependency_incomplete?/1)
      end
    end)
  end

  defp dependency_incomplete?(dep) do
    case dep.task_state do
      %Ash.NotLoaded{} ->
        false

      task_state ->
        case task_state.is_complete do
          %Ash.NotLoaded{} -> false
          is_complete -> not is_complete
        end
    end
  end
end
