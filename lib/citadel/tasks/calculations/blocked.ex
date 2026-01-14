defmodule Citadel.Tasks.Calculations.Blocked do
  @moduledoc """
  Calculates whether a task is blocked by incomplete dependencies.

  Returns:
  - true if any dependency task has an incomplete task_state
  - false if all dependencies are complete or there are no dependencies
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
        %Ash.NotLoaded{} -> false
        dependencies -> Enum.any?(dependencies, &dependency_incomplete?/1)
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
