defmodule Citadel.Tasks.TaskActivity.Types.ActorType do
  @moduledoc false
  use Ash.Type.Enum, values: [:user, :system, :ai]
end
