defmodule Citadel.Tasks.AgentWorkItem.Types.WorkItemType do
  @moduledoc false
  use Ash.Type.Enum, values: [:new_task, :changes_requested, :question_answered]
end
