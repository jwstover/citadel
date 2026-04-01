defmodule Citadel.Tasks.TaskActivity.Types.ActivityType do
  @moduledoc false
  use Ash.Type.Enum,
    values: [:comment, :change_request, :agent_run, :question, :question_response]
end
