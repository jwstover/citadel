defmodule CitadelAgentTest do
  use ExUnit.Case

  test "config/1 reads application config" do
    Application.put_env(:citadel_agent, :citadel_url, "http://test:4000")
    assert CitadelAgent.config(:citadel_url) == "http://test:4000"
  end
end
