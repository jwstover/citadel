defmodule CitadelAgent.RunnersTest do
  use ExUnit.Case, async: false

  alias CitadelAgent.Runners

  setup do
    registry = CitadelAgent.RunnerRegistry

    case GenServer.whereis(registry) do
      nil ->
        start_supervised!({Registry, keys: :unique, name: registry})

      _pid ->
        :ok
    end

    :ok
  end

  test "get_status/0 returns idle when no runners are active" do
    assert {"idle", nil} = Runners.get_status()
  end

  test "get_status/0 returns working when a runner is active" do
    task_id = "task-#{System.unique_integer([:positive])}"
    pid = start_registered_process(task_id)

    assert {"working", ^task_id} = Runners.get_status()

    stop_process(pid)
  end

  test "get_status/0 returns idle after runner terminates" do
    task_id = "task-#{System.unique_integer([:positive])}"
    pid = start_registered_process(task_id)
    stop_process(pid)

    assert {"idle", nil} = Runners.get_status()
  end

  test "has_active_runner?/0 returns false when no runners" do
    refute Runners.has_active_runner?()
  end

  test "has_active_runner?/0 returns true when a runner exists" do
    task_id = "task-#{System.unique_integer([:positive])}"
    pid = start_registered_process(task_id)

    assert Runners.has_active_runner?()

    stop_process(pid)
  end

  test "has_active_runner?/0 returns false after runner crashes" do
    task_id = "task-#{System.unique_integer([:positive])}"
    pid = start_registered_process(task_id)

    kill_and_wait(pid)

    refute Runners.has_active_runner?()
  end

  test "lookup/1 returns pid for active runner" do
    task_id = "task-#{System.unique_integer([:positive])}"
    pid = start_registered_process(task_id)

    assert Runners.lookup(task_id) == pid

    stop_process(pid)
  end

  test "lookup/1 returns nil for unknown task" do
    assert Runners.lookup("nonexistent") == nil
  end

  test "lookup/1 returns nil after runner terminates" do
    task_id = "task-#{System.unique_integer([:positive])}"
    pid = start_registered_process(task_id)
    stop_process(pid)

    assert Runners.lookup(task_id) == nil
  end

  test "crashed runner does not leave stale entries" do
    task_id = "task-#{System.unique_integer([:positive])}"
    pid = start_registered_process(task_id)

    kill_and_wait(pid)

    assert {"idle", nil} = Runners.get_status()
    refute Runners.has_active_runner?()
    assert Runners.lookup(task_id) == nil
  end

  defp start_registered_process(task_id) do
    {:ok, pid} =
      Agent.start(fn -> :running end,
        name: {:via, Registry, {CitadelAgent.RunnerRegistry, task_id}}
      )

    pid
  end

  defp stop_process(pid) do
    ref = Process.monitor(pid)
    Agent.stop(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      1_000 -> raise "Process did not stop in time"
    end

    Process.sleep(10)
  end

  defp kill_and_wait(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      1_000 -> raise "Process did not terminate"
    end

    # Give Registry time to process its own DOWN monitor
    Process.sleep(10)
  end
end
