defmodule CitadelAgent do
  @moduledoc """
  CitadelAgent is a local execution agent that polls Citadel for
  agent-eligible tasks, executes them via Claude Code CLI, and
  reports results back.
  """

  def config(key) do
    Application.get_env(:citadel_agent, key)
  end
end
