defmodule Citadel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    setup_observability()

    children = [
      Citadel.Vault,
      CitadelWeb.Telemetry,
      Citadel.Repo,
      Citadel.PromEx,
      {Registry, keys: :unique, name: Citadel.MCP.ClientRegistry},
      {DynamicSupervisor, name: Citadel.MCP.ClientSupervisor, strategy: :one_for_one},
      {DNSCluster, query: Application.get_env(:citadel, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:citadel, :ash_domains),
         Application.fetch_env!(:citadel, Oban)
       )},
      {Phoenix.PubSub, name: Citadel.PubSub},
      CitadelWeb.AgentPresence,
      Citadel.Settings.FeatureFlagCache,
      # Start a worker by calling: Citadel.Worker.start_link(arg)
      # {Citadel.Worker, arg},
      # Start to serve requests, typically the last entry
      CitadelWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :citadel]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Citadel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CitadelWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp setup_observability do
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryBandit.setup()
    OpentelemetryEcto.setup([:citadel, :repo])
    OpentelemetryOban.setup()
    OpentelemetryLoggerMetadata.setup()

    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{
        metadata: [:request_id, :trace_id, :span_id],
        capture_log_messages: true,
        level: :error
      }
    })

    log_otlp_diagnostics()
  end

  defp log_otlp_diagnostics do
    endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")
    raw_headers = System.get_env("OTEL_EXPORTER_OTLP_HEADERS", "")

    header_names =
      raw_headers
      |> String.split(",", trim: true)
      |> Enum.map(fn kv ->
        case String.split(kv, "=", parts: 2) do
          [k, _v] -> String.trim(k)
          _ -> "<unparseable>"
        end
      end)

    require Logger

    Logger.info(
      "otlp diagnostics: endpoint=#{inspect(endpoint)} header_names=#{inspect(header_names)} header_count=#{length(header_names)}"
    )
  end
end
