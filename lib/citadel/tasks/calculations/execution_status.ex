defmodule Citadel.Tasks.Calculations.ExecutionStatus do
  @moduledoc false
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:active_agent_run]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.active_agent_run do
        %Ash.NotLoaded{} -> :none
        nil -> :none
        run -> run.status
      end
    end)
  end
end
