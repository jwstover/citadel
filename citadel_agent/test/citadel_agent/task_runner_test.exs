defmodule CitadelAgent.TaskRunnerTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    System.cmd("git", ["init", "-b", "main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)
    File.write!(Path.join(tmp_dir, "README.md"), "# Test")
    System.cmd("git", ["add", "."], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    registry = CitadelAgent.RunnerRegistry

    case GenServer.whereis(registry) do
      nil -> start_supervised!({Registry, keys: :unique, name: registry})
      _pid -> :ok
    end

    original_url = CitadelAgent.config(:citadel_url)
    Application.put_env(:citadel_agent, :citadel_url, "http://127.0.0.1:1")
    on_exit(fn -> Application.put_env(:citadel_agent, :citadel_url, original_url) end)

    task = %{
      "id" => "task-#{System.unique_integer([:positive])}",
      "human_id" => "TEST-#{System.unique_integer([:positive])}",
      "title" => "Test task",
      "description" => "A test task"
    }

    run = %{"id" => "run-#{System.unique_integer([:positive])}"}

    {:ok, task: task, run: run, project_path: tmp_dir}
  end

  test "registers in RunnerRegistry on start", ctx do
    {:ok, pid} = start_task_runner(ctx)

    assert [{^pid, _}] = Registry.lookup(CitadelAgent.RunnerRegistry, ctx.task["id"])

    wait_for_exit(pid)
  end

  test "deregisters from RunnerRegistry after execution completes", ctx do
    {:ok, pid} = start_task_runner(ctx)
    wait_for_exit(pid)

    assert [] = Registry.lookup(CitadelAgent.RunnerRegistry, ctx.task["id"])
  end

  test "stops itself after execution", ctx do
    {:ok, pid} = start_task_runner(ctx)
    ref = Process.monitor(pid)

    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 10_000
    refute Process.alive?(pid)
  end

  test "deregisters from RunnerRegistry after crash", ctx do
    Process.flag(:trap_exit, true)
    {:ok, pid} = start_task_runner(ctx)

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^ref, :process, ^pid, :killed} -> :ok
    after
      5_000 -> raise "Process did not terminate"
    end

    Process.sleep(10)

    assert [] = Registry.lookup(CitadelAgent.RunnerRegistry, ctx.task["id"])
  end

  test "does not allow duplicate runners for same task", ctx do
    {:ok, pid} = start_task_runner(ctx)

    assert {:error, {:already_started, ^pid}} = start_task_runner(ctx)

    wait_for_exit(pid)
  end

  defp start_task_runner(ctx) do
    CitadelAgent.TaskRunner.start_link(%{
      task: ctx.task,
      run: ctx.run,
      project_path: ctx.project_path
    })
  end

  defp wait_for_exit(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      10_000 -> raise "TaskRunner did not exit in time"
    end
  end
end
