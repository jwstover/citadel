defmodule Citadel.Tasks.AgentWorkItem.Types.WorkItemStatus do
  @moduledoc false
  use Ash.Type.Enum, values: [:pending, :claimed, :completed, :cancelled]
end
