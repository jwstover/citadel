defmodule CitadelAgent.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if CitadelAgent.config(:api_key) do
        CitadelAgent.Preflight.run!()

        [
          {Registry, keys: :unique, name: CitadelAgent.RunnerRegistry},
          {DynamicSupervisor, name: CitadelAgent.RunnerSupervisor, strategy: :one_for_one},
          {CitadelAgent.Socket, []},
          {CitadelAgent.Scheduler, []}
        ]
      else
        []
      end

    opts = [strategy: :one_for_one, name: CitadelAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
