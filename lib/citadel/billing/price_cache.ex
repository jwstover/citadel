defmodule Citadel.Billing.PriceCache do
  @moduledoc """
  ETS-backed cache for Stripe plan prices with a periodic TTL refresh.

  On startup the GenServer fetches live unit_amount values from Stripe for
  each configured price ID. If Stripe is unreachable, or a price ID is not
  yet configured (e.g. in dev/test), it falls back to the hardcoded defaults
  in `Citadel.Billing.Plan`. The cache is refreshed automatically every hour.

  ## Usage

      Citadel.Billing.PriceCache.get_plan_prices()
      #=> %{pro_monthly_cents: 1900, pro_annual_cents: 19000,
      #=>   pro_seat_monthly_cents: 500, pro_seat_annual_cents: 5000}
  """

  use GenServer
  require Logger

  alias Citadel.Billing.Plan

  @table_name :billing_price_cache
  @ttl_ms :timer.hours(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns cached plan prices. Falls back to Plan defaults if the cache is
  not yet populated or the ETS table is unavailable.
  """
  @spec get_plan_prices() :: map()
  def get_plan_prices do
    case :ets.lookup(@table_name, :prices) do
      [{:prices, prices}] -> prices
      [] -> fallback_prices()
    end
  rescue
    ArgumentError -> fallback_prices()
  end

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:set, :protected, :named_table, read_concurrency: true])
    send(self(), :refresh)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:refresh, state) do
    prices = fetch_prices()
    :ets.insert(@table_name, {:prices, prices})
    Process.send_after(self(), :refresh, @ttl_ms)
    {:noreply, state}
  end

  defp fetch_prices do
    defaults = fallback_prices()

    %{
      pro_monthly_cents:
        fetch_price_or_default(Plan.stripe_price_id(:pro, :monthly), defaults.pro_monthly_cents),
      pro_annual_cents:
        fetch_price_or_default(Plan.stripe_price_id(:pro, :annual), defaults.pro_annual_cents),
      pro_seat_monthly_cents:
        fetch_price_or_default(
          Plan.stripe_seat_price_id(:pro, :monthly),
          defaults.pro_seat_monthly_cents
        ),
      pro_seat_annual_cents:
        fetch_price_or_default(
          Plan.stripe_seat_price_id(:pro, :annual),
          defaults.pro_seat_annual_cents
        )
    }
  end

  defp fetch_price_or_default(nil, default), do: default

  defp fetch_price_or_default(price_id, default) do
    case Stripe.Price.retrieve(price_id) do
      {:ok, %{unit_amount: amount}} when is_integer(amount) ->
        amount

      {:ok, _} ->
        default

      {:error, error} ->
        Logger.warning("Failed to fetch Stripe price #{price_id}: #{inspect(error)}")
        default
    end
  end

  defp fallback_prices do
    %{
      pro_monthly_cents: Plan.base_price_cents(:pro, :monthly),
      pro_annual_cents: Plan.base_price_cents(:pro, :annual),
      pro_seat_monthly_cents: Plan.per_member_price_cents(:pro, :monthly),
      pro_seat_annual_cents: Plan.per_member_price_cents(:pro, :annual)
    }
  end
end
