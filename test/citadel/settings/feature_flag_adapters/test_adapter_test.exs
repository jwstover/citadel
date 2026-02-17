defmodule Citadel.Settings.FeatureFlagAdapters.TestAdapterTest do
  use ExUnit.Case, async: true

  alias Citadel.Settings.FeatureFlagAdapters.TestAdapter

  setup do
    # Ensure clean state for each test
    TestAdapter.clear_feature_flags()
    :ok
  end

  describe "get/1" do
    test "returns :not_found when flag doesn't exist" do
      assert :not_found = TestAdapter.get(:nonexistent)
    end

    test "returns {:ok, value} when flag exists" do
      TestAdapter.set_feature_flag(:test_flag, true)
      assert {:ok, true} = TestAdapter.get(:test_flag)

      TestAdapter.set_feature_flag(:test_flag, false)
      assert {:ok, false} = TestAdapter.get(:test_flag)
    end
  end

  describe "set_feature_flag/2" do
    test "sets a single feature flag" do
      assert :ok = TestAdapter.set_feature_flag(:api_access, true)
      assert {:ok, true} = TestAdapter.get(:api_access)
    end

    test "overwrites existing flag value" do
      TestAdapter.set_feature_flag(:feature, true)
      assert {:ok, true} = TestAdapter.get(:feature)

      TestAdapter.set_feature_flag(:feature, false)
      assert {:ok, false} = TestAdapter.get(:feature)
    end

    test "multiple flags can coexist" do
      TestAdapter.set_feature_flag(:flag1, true)
      TestAdapter.set_feature_flag(:flag2, false)

      assert {:ok, true} = TestAdapter.get(:flag1)
      assert {:ok, false} = TestAdapter.get(:flag2)
    end
  end

  describe "set_feature_flags/1" do
    test "sets multiple flags at once" do
      flags = %{
        api_access: true,
        ai_chat: false,
        bulk_import: true
      }

      assert :ok = TestAdapter.set_feature_flags(flags)

      assert {:ok, true} = TestAdapter.get(:api_access)
      assert {:ok, false} = TestAdapter.get(:ai_chat)
      assert {:ok, true} = TestAdapter.get(:bulk_import)
    end

    test "merges with existing flags" do
      TestAdapter.set_feature_flag(:existing, true)

      TestAdapter.set_feature_flags(%{
        new_flag: false
      })

      assert {:ok, true} = TestAdapter.get(:existing)
      assert {:ok, false} = TestAdapter.get(:new_flag)
    end

    test "overwrites existing flag values" do
      TestAdapter.set_feature_flag(:feature, true)
      assert {:ok, true} = TestAdapter.get(:feature)

      TestAdapter.set_feature_flags(%{feature: false})
      assert {:ok, false} = TestAdapter.get(:feature)
    end
  end

  describe "clear_feature_flags/0" do
    test "removes all flags" do
      TestAdapter.set_feature_flags(%{
        flag1: true,
        flag2: false,
        flag3: true
      })

      assert {:ok, true} = TestAdapter.get(:flag1)

      TestAdapter.clear_feature_flags()

      assert :not_found = TestAdapter.get(:flag1)
      assert :not_found = TestAdapter.get(:flag2)
      assert :not_found = TestAdapter.get(:flag3)
    end

    test "works when no flags are set" do
      assert :ok = TestAdapter.clear_feature_flags()
    end
  end

  describe "refresh/0" do
    test "is a no-op and returns :ok" do
      assert :ok = TestAdapter.refresh()
    end
  end

  describe "test isolation" do
    test "flags are shared within a test (important for LiveView)" do
      # Set flag in current test process
      TestAdapter.set_feature_flag(:shared_flag, true)
      assert {:ok, true} = TestAdapter.get(:shared_flag)

      # Spawn a new process (simulating LiveView) and verify it sees the flag
      task =
        Task.async(fn ->
          TestAdapter.get(:shared_flag)
        end)

      # The flag is visible because both processes share the same group leader
      assert {:ok, true} = Task.await(task)
    end

    test "flags can be modified from any process in the test" do
      TestAdapter.set_feature_flag(:modifiable_flag, true)
      assert {:ok, true} = TestAdapter.get(:modifiable_flag)

      task =
        Task.async(fn ->
          TestAdapter.set_feature_flag(:modifiable_flag, false)
          TestAdapter.get(:modifiable_flag)
        end)

      assert {:ok, false} = Task.await(task)
      # Value is shared, so main process sees the change too
      assert {:ok, false} = TestAdapter.get(:modifiable_flag)
    end
  end
end
