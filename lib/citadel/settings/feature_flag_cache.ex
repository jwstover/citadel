defmodule Citadel.Settings.FeatureFlagCache do
  @moduledoc """
  ETS-based cache for feature flags with PubSub invalidation.

  This GenServer maintains an in-memory cache of feature flags to avoid
  database lookups on every feature check. The cache is automatically
  invalidated when flags are created, updated, or deleted via PubSub.

  ## Cache Strategy

  - All feature flags are loaded into ETS on startup
  - Cache is invalidated on any flag change (create/update/destroy)
  - Lookups are O(1) from ETS
  - Falls back to default behavior if cache is unavailable

  ## Usage

      # Check if a feature flag exists and is enabled
      FeatureFlagCache.get(:api_access)
      #=> {:ok, true}  # Flag exists and is enabled
      #=> {:ok, false} # Flag exists but is disabled
      #=> :not_found   # Flag doesn't exist (falls back to tier check)
  """
  use GenServer
  require Logger

  @table_name :feature_flags_cache

  # Client API

  @doc """
  Starts the cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a feature flag value from the cache.

  Returns:
  - `{:ok, true}` if flag exists and is enabled
  - `{:ok, false}` if flag exists but is disabled
  - `:not_found` if flag doesn't exist in cache
  """
  @spec get(atom()) :: {:ok, boolean()} | :not_found
  def get(key) when is_atom(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, enabled}] -> {:ok, enabled}
      [] -> :not_found
    end
  rescue
    ArgumentError ->
      Logger.warning("Feature flag cache not available, falling back to uncached lookup")
      :not_found
  end

  @doc """
  Forces a cache refresh from the database.
  """
  @spec refresh() :: :ok
  def refresh do
    GenServer.cast(__MODULE__, :refresh_cache)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:set, :protected, :named_table, read_concurrency: true])

    # Subscribe to PubSub for cache invalidation
    Phoenix.PubSub.subscribe(Citadel.PubSub, "feature_flags:changed")

    # Load initial data
    load_flags_into_cache()

    {:ok, %{}}
  end

  @impl true
  def handle_cast(:refresh_cache, state) do
    load_flags_into_cache()
    {:noreply, state}
  end

  @impl true
  def handle_info(%{topic: "feature_flags:changed"}, state) do
    Logger.debug("Feature flag changed, refreshing cache")
    load_flags_into_cache()
    {:noreply, state}
  end

  # Private Functions

  defp load_flags_into_cache do
    flags = Citadel.Settings.list_feature_flags!(authorize?: false)

    :ets.delete_all_objects(@table_name)

    Enum.each(flags, fn flag ->
      :ets.insert(@table_name, {flag.key, flag.enabled})
    end)

    Logger.debug("Loaded #{length(flags)} feature flags into cache")
  rescue
    e ->
      Logger.debug("FeatureFlagCache init deferred: #{inspect(e)}")
  end
end
