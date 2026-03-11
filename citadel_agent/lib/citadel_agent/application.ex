defmodule CitadelAgent.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if CitadelAgent.config(:api_key) do
        CitadelAgent.Preflight.run!()
        [{CitadelAgent.Worker, []}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: CitadelAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
