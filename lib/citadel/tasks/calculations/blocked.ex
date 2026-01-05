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
    [dependencies: [:task_state]]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.dependencies do
        %Ash.NotLoaded{} ->
          false

        dependencies ->
          Enum.any?(dependencies, fn dep ->
            case dep.task_state do
              %Ash.NotLoaded{} -> false
              task_state -> not task_state.is_complete
            end
          end)
      end
    end)
  end
end
