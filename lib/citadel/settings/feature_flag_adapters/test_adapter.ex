defmodule Citadel.Settings.FeatureFlagAdapters.TestAdapter do
  @moduledoc """
  Test adapter that uses an ETS table for fast, isolated tests.

  Uses a per-test ETS table (scoped by test process PID) to store feature flags.
  This enables:
  - Tests to run with `async: true`
  - Zero sleep delays for flag propagation
  - Automatic cleanup when test process exits (via heir mechanism)
  - Works across processes (important for LiveView tests)
  - Simple API: `set_feature_flag(:flag_name, true)`
  """

  @behaviour Citadel.Settings.FeatureFlagAdapter

  @table_prefix :feature_flags_test

  @impl true
  def get(key) when is_atom(key) do
    table = get_or_create_table()

    case :ets.lookup(table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :not_found
    end
  end

  @impl true
  def refresh do
    :ok
  end

  @doc """
  Sets a single feature flag value for the current test.

  ## Example

      set_feature_flag(:api_access, true)
  """
  def set_feature_flag(key, value) when is_atom(key) and is_boolean(value) do
    table = get_or_create_table()
    :ets.insert(table, {key, value})
    :ok
  end

  @doc """
  Sets multiple feature flags at once.

  ## Example

      set_feature_flags(%{
        api_access: true,
        ai_chat: false
      })
  """
  def set_feature_flags(flags) when is_map(flags) do
    table = get_or_create_table()

    Enum.each(flags, fn {key, value} ->
      :ets.insert(table, {key, value})
    end)

    :ok
  end

  @doc """
  Clears all feature flags for the current test.
  """
  def clear_feature_flags do
    table = get_or_create_table()
    :ets.delete_all_objects(table)
    :ok
  end

  # Gets or creates a test-specific ETS table
  # Uses $callers to find the root test process
  # This ensures all processes spawned by the test (like LiveViews) share the same table
  defp get_or_create_table do
    # Get the root caller (test process) from the $callers list
    # When a LiveView spawns, $callers contains [test_pid, ...]
    test_pid =
      case Process.get(:"$callers") do
        [root | _] -> root
        _ -> self()
      end

    test_id = :erlang.phash2(test_pid)
    table_name = :"#{@table_prefix}_#{test_id}"

    case :ets.whereis(table_name) do
      :undefined ->
        # Create table as public so all processes can access it
        :ets.new(table_name, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        table_name
    end
  end
end
