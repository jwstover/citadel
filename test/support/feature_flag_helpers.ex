defmodule Citadel.TestSupport.FeatureFlagHelpers do
  @moduledoc """
  Test helpers for feature flag manipulation in tests.

  These helpers wrap the TestAdapter for convenient feature flag setup
  in tests without requiring GenServer coordination or PubSub delays.

  ## Usage

      use Citadel.DataCase, async: true

      test "feature gated behavior" do
        enable_feature(:api_access)

        # Test code that checks the feature flag
      end

  ## Setup Hook

  For tests that need specific flags based on test tags:

      @tag features: %{api_access: true, ai_chat: false}
      test "with specific features", %{features: features} do
        # features automatically set via with_features/1
      end
  """

  alias Citadel.Settings.FeatureFlagAdapters.TestAdapter

  @doc """
  Enables a feature flag for the current test process.

  ## Example

      enable_feature(:api_access)
  """
  def enable_feature(key) when is_atom(key) do
    TestAdapter.set_feature_flag(key, true)
  end

  @doc """
  Disables a feature flag for the current test process.

  ## Example

      disable_feature(:ai_chat)
  """
  def disable_feature(key) when is_atom(key) do
    TestAdapter.set_feature_flag(key, false)
  end

  @doc """
  Sets multiple feature flags at once.

  ## Example

      set_features(%{
        api_access: true,
        ai_chat: false
      })
  """
  def set_features(flags) when is_map(flags) do
    TestAdapter.set_feature_flags(flags)
  end

  @doc """
  Clears all feature flags for the current test process.

  Useful in setup blocks if you want to ensure a clean slate.

  ## Example

      setup do
        clear_features()
        :ok
      end
  """
  def clear_features do
    TestAdapter.clear_feature_flags()
  end

  @doc """
  Setup helper that automatically sets features from test context.

  Use with test tags to declaratively set feature flags:

  ## Example

      setup :with_features

      @tag features: %{api_access: true}
      test "with features", _context do
        # api_access is automatically enabled
      end
  """
  def with_features(%{features: flags}) when is_map(flags) do
    TestAdapter.set_feature_flags(flags)
    :ok
  end

  def with_features(_context), do: :ok
end
