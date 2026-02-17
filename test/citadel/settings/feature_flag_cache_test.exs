defmodule Citadel.Settings.FeatureFlagCacheTest do
  # This test file specifically tests the GenServer/ETS cache implementation
  # and must remain non-async to test the actual production behavior.
  # Other tests use the TestAdapter for fast, async testing.
  use Citadel.DataCase, async: false

  alias Citadel.Settings
  alias Citadel.Settings.FeatureFlagCache

  setup do
    # Ensure cache is refreshed before each test
    FeatureFlagCache.refresh()
    Process.sleep(100)
    :ok
  end

  describe "cache lookups" do
    test "returns enabled status when flag exists" do
      Settings.create_feature_flag(%{key: :api_access, enabled: true}, authorize?: false)
      FeatureFlagCache.refresh()
      Process.sleep(50)

      assert {:ok, true} = FeatureFlagCache.get(:api_access)
    end

    test "returns disabled status when flag exists but is disabled" do
      Settings.create_feature_flag(%{key: :webhooks, enabled: false}, authorize?: false)
      FeatureFlagCache.refresh()
      Process.sleep(50)

      assert {:ok, false} = FeatureFlagCache.get(:webhooks)
    end

    test "returns :not_found when flag does not exist" do
      assert :not_found = FeatureFlagCache.get(:nonexistent_feature)
    end
  end

  describe "cache invalidation via PubSub" do
    test "cache updates when flag is created" do
      # Initially not found
      assert :not_found = FeatureFlagCache.get(:bulk_import)

      # Create flag
      Settings.create_feature_flag(%{key: :bulk_import, enabled: true}, authorize?: false)

      # Give PubSub time to propagate
      Process.sleep(100)

      # Now should be in cache
      assert {:ok, true} = FeatureFlagCache.get(:bulk_import)
    end

    test "cache updates when flag is updated" do
      Settings.create_feature_flag(%{key: :data_export, enabled: false}, authorize?: false)
      FeatureFlagCache.refresh()
      Process.sleep(50)

      assert {:ok, false} = FeatureFlagCache.get(:data_export)

      # Update flag
      {:ok, flag} = Settings.get_feature_flag_by_key(:data_export, authorize?: false)
      Settings.update_feature_flag(flag, %{enabled: true}, authorize?: false)

      # Give PubSub time to propagate
      Process.sleep(100)

      # Cache should reflect update
      assert {:ok, true} = FeatureFlagCache.get(:data_export)
    end

    test "cache updates when flag is deleted" do
      Settings.create_feature_flag(%{key: :custom_branding, enabled: true}, authorize?: false)
      FeatureFlagCache.refresh()
      Process.sleep(50)

      assert {:ok, true} = FeatureFlagCache.get(:custom_branding)

      # Delete flag
      {:ok, flag} = Settings.get_feature_flag_by_key(:custom_branding, authorize?: false)
      Settings.delete_feature_flag(flag, authorize?: false)

      # Give PubSub time to propagate
      Process.sleep(100)

      # Cache should show flag removed
      assert :not_found = FeatureFlagCache.get(:custom_branding)
    end
  end

  describe "cache performance" do
    test "cache lookups are fast" do
      Settings.create_feature_flag(%{key: :priority_support, enabled: true}, authorize?: false)
      FeatureFlagCache.refresh()
      Process.sleep(50)

      # Measure lookup time
      {time, result} = :timer.tc(fn -> FeatureFlagCache.get(:priority_support) end)

      assert {:ok, true} = result
      # ETS lookups should be sub-millisecond
      assert time < 1000
    end
  end
end
