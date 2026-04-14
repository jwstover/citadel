defmodule CitadelWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import Citadel.Generator

      @endpoint CitadelWeb.Endpoint
    end
  end

  setup tags do
    Citadel.DataCase.setup_sandbox(tags)
    :ok
  end
end
