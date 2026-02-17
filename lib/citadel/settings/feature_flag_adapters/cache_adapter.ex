defmodule Citadel.Settings.FeatureFlagAdapters.CacheAdapter do
  @moduledoc """
  Production adapter that delegates to the FeatureFlagCache GenServer.

  This adapter wraps the existing ETS-backed cache for production use.
  """

  @behaviour Citadel.Settings.FeatureFlagAdapter

  alias Citadel.Settings.FeatureFlagCache

  @impl true
  def get(key) when is_atom(key) do
    FeatureFlagCache.get(key)
  end

  @impl true
  def refresh do
    FeatureFlagCache.refresh()
  end
end
