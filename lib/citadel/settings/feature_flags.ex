defmodule Citadel.Settings.FeatureFlags do
  @moduledoc """
  Public API for accessing feature flags.

  Delegates to the configured adapter (ETS cache in production,
  process dictionary in tests).

  ## Configuration

      # config/config.exs
      config :citadel, :feature_flag_adapter,
        Citadel.Settings.FeatureFlagAdapters.CacheAdapter

      # config/test.exs
      config :citadel, :feature_flag_adapter,
        Citadel.Settings.FeatureFlagAdapters.TestAdapter
  """

  @doc """
  Gets the value of a feature flag.

  Returns `{:ok, boolean()}` if the flag exists, or `:not_found` if it doesn't.

  ## Examples

      iex> FeatureFlags.get(:ai_chat)
      {:ok, true}

      iex> FeatureFlags.get(:nonexistent)
      :not_found
  """
  def get(key) when is_atom(key) do
    adapter().get(key)
  end

  @doc """
  Refreshes the feature flag cache.

  In production, triggers a GenServer refresh. In tests, this is a no-op.
  """
  def refresh do
    adapter().refresh()
  end

  defp adapter do
    Application.get_env(:citadel, :feature_flag_adapter)
  end
end
