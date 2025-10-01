defmodule Citadel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CitadelWeb.Telemetry,
      Citadel.Repo,
      {DNSCluster, query: Application.get_env(:citadel, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Citadel.PubSub},
      # Start a worker by calling: Citadel.Worker.start_link(arg)
      # {Citadel.Worker, arg},
      # Start to serve requests, typically the last entry
      CitadelWeb.Endpoint
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
end
