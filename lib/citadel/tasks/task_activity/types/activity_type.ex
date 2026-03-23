defmodule Citadel.Tasks.TaskActivity.Types.ActivityType do
  @moduledoc false
  use Ash.Type.Enum, values: [:comment, :change_request, :question, :question_response]
end
