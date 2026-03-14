defmodule CitadelAgent.TaskRunner do
  @moduledoc """
  A GenServer that wraps task execution, registering itself in the RunnerRegistry
  via `:via` tuple naming. When the process terminates for any reason, the Registry
  automatically deregisters it.
  """

  use GenServer

  require Logger

  def start_link(args) do
    task_id = Keyword.fetch!(args, :task_id)

    GenServer.start_link(__MODULE__, args,
      name: {:via, Registry, {CitadelAgent.RunnerRegistry, task_id}}
    )
  end

  @impl true
  def init(args) do
    task = Keyword.fetch!(args, :task)
    project_path = Keyword.fetch!(args, :project_path)
    task_id = Keyword.fetch!(args, :task_id)

    {:ok, %{task: task, project_path: project_path, task_id: task_id, result: nil},
     {:continue, :execute}}
  end

  @impl true
  def handle_continue(:execute, state) do
    result = CitadelAgent.Runner.execute(state.task, state.project_path)
    {:stop, {:shutdown, result}, %{state | result: result}}
  rescue
    e ->
      {:stop, {:shutdown, {:error, Exception.message(e)}}, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
