defmodule Citadel.PromEx do
  @moduledoc """
  PromEx instrumentation for Citadel. Emits Prometheus metrics for the BEAM
  VM, application info, Phoenix request handling, Ecto queries, Oban jobs,
  and Phoenix LiveView.

  In prod these are pushed to Grafana Cloud Prometheus via the
  `prometheus_remote_write` exporter (configured in `config/runtime.exs`).
  Pre-built Grafana dashboards ship with each plugin under `deps/prom_ex/`.
  """

  use PromEx, otp_app: :citadel

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: CitadelWeb.Router, endpoint: CitadelWeb.Endpoint},
      Plugins.Ecto,
      Plugins.Oban,
      Plugins.PhoenixLiveView
    ]
  end

  @impl true
  def dashboard_assigns do
    [datasource_id: "prometheus", default_selected_interval: "30s"]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"},
      {:prom_ex, "phoenix_live_view.json"}
    ]
  end
end
