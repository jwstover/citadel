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

  describe "terminate/2" do
    setup ctx do
      Req.Test.set_req_test_to_shared()

      original_req_opts = Application.get_env(:citadel_agent, :client_req_options)
      Application.put_env(:citadel_agent, :client_req_options, plug: {Req.Test, :citadel_api})

      on_exit(fn ->
        Req.Test.set_req_test_to_private()

        if original_req_opts do
          Application.put_env(:citadel_agent, :client_req_options, original_req_opts)
        else
          Application.delete_env(:citadel_agent, :client_req_options)
        end
      end)

      ctx
    end

    test "calls update_run with failed status when active_run is set", ctx do
      test_pid = self()
      run_id = ctx.run["id"]

      Req.Test.stub(:citadel_api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:update_run, conn.request_path, Jason.decode!(body)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => %{"id" => run_id}}))
      end)

      state = %{active_run: ctx.run, task: ctx.task, project_path: ctx.project_path}

      CitadelAgent.TaskRunner.terminate(:test_crash, state)

      assert_receive {:update_run, path, body}, 2_000
      assert path == "/api/agent/runs/#{run_id}"
      assert body["status"] == "failed"
      assert body["error_message"] =~ "terminated"
      assert body["completed_at"]
    end

    test "is a no-op for normal exit" do
      assert :ok = CitadelAgent.TaskRunner.terminate(:normal, %{})
    end

    test "handles nil active_run on abnormal exit" do
      state = %{active_run: nil, task: %{}, project_path: "/tmp"}
      CitadelAgent.TaskRunner.terminate(:shutdown, state)
    end
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

    Process.sleep(10)
  end
end
