defmodule Citadel.Tasks.Calculations.DaysUntilDue do
  @moduledoc """
  Calculates the number of days until the task's due date.

  Returns:
  - Positive integer if due date is in the future
  - Negative integer if due date is in the past (overdue)
  - 0 if due date is today
  - nil if no due date is set
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:due_date]
  end

  @impl true
  def calculate(records, _opts, _context) do
    today = Date.utc_today()

    Enum.map(records, fn record ->
      case record.due_date do
        nil -> nil
        due_date -> Date.diff(due_date, today)
      end
    end)
  end
end
