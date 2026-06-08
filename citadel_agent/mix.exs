defmodule CitadelAgent.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :citadel_agent,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CitadelAgent.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:slipstream, "~> 1.1"},
      {:erlexec, "~> 2.0"},
      {:plug, "~> 1.0", only: :test}
    ]
  end

  defp releases do
    [
      citadel_agent: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent, erlexec: :permanent]
      ]
    ]
  end
end
