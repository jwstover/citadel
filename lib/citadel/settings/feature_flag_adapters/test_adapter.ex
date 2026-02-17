defmodule Citadel.Settings.FeatureFlagAdapters.TestAdapter do
  @moduledoc """
  Test adapter that uses an ETS table for fast, isolated tests.

  Uses a shared ETS table with composite keys `{test_id, flag_key}` to store feature flags.
  This enables:
  - Tests to run with `async: true`
  - Zero sleep delays for flag propagation
  - Works across processes (important for LiveView tests)
  - Simple API: `set_feature_flag(:flag_name, true)`
  """

  @behaviour Citadel.Settings.FeatureFlagAdapter

  @table_name :citadel_feature_flags_test

  @impl true
  def get(key) when is_atom(key) do
    table = get_or_create_table()
    test_id = get_test_id()
    composite_key = {test_id, key}

    case :ets.lookup(table, composite_key) do
      [{^composite_key, value}] -> {:ok, value}
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
    test_id = get_test_id()
    :ets.insert(table, {{test_id, key}, value})
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
    test_id = get_test_id()

    Enum.each(flags, fn {key, value} ->
      :ets.insert(table, {{test_id, key}, value})
    end)

    :ok
  end

  @doc """
  Clears all feature flags for the current test.
  """
  def clear_feature_flags do
    table = get_or_create_table()
    test_id = get_test_id()
    :ets.match_delete(table, {{test_id, :_}, :_})
    :ok
  end

  defp get_test_id do
    test_pid =
      case Process.get(:"$callers") do
        [root | _] -> root
        _ -> self()
      end

    :erlang.phash2(test_pid)
  end

  defp get_or_create_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        @table_name
    end
  end
end
