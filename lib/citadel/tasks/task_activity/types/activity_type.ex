defmodule Citadel.Tasks.TaskActivity.Types.ActivityType do
  @moduledoc false
  use Ash.Type.Enum, values: [:comment, :agent_run]
end
