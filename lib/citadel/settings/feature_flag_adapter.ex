defmodule Citadel.Settings.FeatureFlagAdapter do
  @moduledoc """
  Behavior for feature flag storage adapters.

  Adapters implement different storage strategies for feature flags:
  - Production: ETS-backed GenServer cache
  - Test: Process dictionary for isolated, fast tests
  """

  @callback get(atom()) :: {:ok, boolean()} | :not_found
  @callback refresh() :: :ok
end
