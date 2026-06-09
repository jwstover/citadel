defmodule CitadelAgent.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = boot_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: CitadelAgent.Supervisor)
  end

  defp boot_children do
    cond do
      not running_as_release?() ->
        []

      is_nil(CitadelAgent.config(:api_key)) ->
        IO.puts(:stderr, "CITADEL_API_KEY is not set. Refusing to start.")
        System.halt(1)

      true ->
        try do
          CitadelAgent.Preflight.run!()

          [
            {CitadelAgent.Socket, []},
            {CitadelAgent.Worker, []}
          ]
        rescue
          e in CitadelAgent.Preflight.CheckError ->
            IO.puts(:stderr, "Preflight failed: #{Exception.message(e)}")
            System.halt(1)
        end
    end
  end

  defp running_as_release?, do: not is_nil(System.get_env("RELEASE_NAME"))
end
