defmodule Citadel.Tasks.Task.Types.Priority do
  @moduledoc """
  Enum type for task priorities: `:low`, `:medium`, `:high`, or `:urgent`.
  """
  use Ash.Type.Enum, values: [:low, :medium, :high, :urgent]
end
