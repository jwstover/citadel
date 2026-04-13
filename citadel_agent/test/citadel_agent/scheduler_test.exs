defmodule CitadelAgent.SchedulerTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup :set_req_test_from_context

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

    sup = CitadelAgent.TaskRunnerSupervisor

    case GenServer.whereis(sup) do
      nil -> start_supervised!({DynamicSupervisor, name: sup, strategy: :one_for_one})
      _pid -> :ok
    end

    app_supervisor_running? = GenServer.whereis(CitadelAgent.Supervisor) != nil

    if app_supervisor_running? do
      Supervisor.terminate_child(CitadelAgent.Supervisor, CitadelAgent.Scheduler)
    end

    original_url = CitadelAgent.config(:citadel_url)
    original_path = CitadelAgent.config(:project_path)
    original_interval = CitadelAgent.config(:poll_interval)
    original_api_key = CitadelAgent.config(:api_key)
    original_req_opts = Application.get_env(:citadel_agent, :client_req_options)

    Application.put_env(:citadel_agent, :citadel_url, "http://localhost:4000")
    Application.put_env(:citadel_agent, :project_path, tmp_dir)
    Application.put_env(:citadel_agent, :poll_interval, 600_000)
    Application.put_env(:citadel_agent, :api_key, "test-key")
    Application.put_env(:citadel_agent, :client_req_options, plug: {Req.Test, :citadel_api})

    on_exit(fn ->
      Application.put_env(:citadel_agent, :citadel_url, original_url)
      Application.put_env(:citadel_agent, :project_path, original_path)
      Application.put_env(:citadel_agent, :poll_interval, original_interval)
      Application.put_env(:citadel_agent, :api_key, original_api_key)

      if original_req_opts do
        Application.put_env(:citadel_agent, :client_req_options, original_req_opts)
      else
        Application.delete_env(:citadel_agent, :client_req_options)
      end

      if app_supervisor_running? do
        Supervisor.restart_child(CitadelAgent.Supervisor, CitadelAgent.Scheduler)
      end
    end)

    {:ok, project_path: tmp_dir}
  end

  defp set_req_test_from_context(_context) do
    Req.Test.set_req_test_to_shared()
    :ok
  end

  test "skips dispatch when a runner is already active" do
    task_id = "task-#{System.unique_integer([:positive])}"

    {:ok, agent} =
      Agent.start(fn -> :running end,
        name: {:via, Registry, {CitadelAgent.RunnerRegistry, task_id}}
      )

    test_pid = self()

    Req.Test.stub(:citadel_api, fn conn ->
      send(test_pid, :claim_task_called)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(204, "")
    end)

    {:ok, _} = start_supervised(CitadelAgent.Scheduler)

    Process.sleep(100)

    refute_received :claim_task_called

    Agent.stop(agent)
  end

  test "claims task and spawns TaskRunner when no runner is active" do
    task_id = "task-#{System.unique_integer([:positive])}"
    human_id = "TEST-#{System.unique_integer([:positive])}"
    run_id = "run-#{System.unique_integer([:positive])}"

    Req.Test.stub(:citadel_api, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/agent/tasks/claim"} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "data" => %{
                "task" => %{
                  "id" => task_id,
                  "human_id" => human_id,
                  "title" => "Test task",
                  "description" => "A test"
                },
                "agent_run" => %{"id" => run_id}
              }
            })
          )

        {"PATCH", "/api/agent/runs/" <> _} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{"data" => %{"id" => run_id, "status" => "failed"}})
          )

        _ ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => []}))
      end
    end)

    {:ok, _} = start_supervised(CitadelAgent.Scheduler)

    assert wait_until(fn ->
             case Registry.lookup(CitadelAgent.RunnerRegistry, task_id) do
               [{_pid, _}] -> true
               [] -> false
             end
           end),
           "TaskRunner was never spawned for #{task_id}"

    wait_until(fn ->
      Registry.lookup(CitadelAgent.RunnerRegistry, task_id) == []
    end)
  end

  test "does not spawn runner when claim returns no tasks" do
    test_pid = self()

    Req.Test.stub(:citadel_api, fn conn ->
      send(test_pid, :claim_called)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(204, "")
    end)

    {:ok, _} = start_supervised(CitadelAgent.Scheduler)

    assert_receive :claim_called, 2_000

    Process.sleep(50)

    refute CitadelAgent.Runners.has_active_runner?()
  end

  defp wait_until(fun, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    if fun.() do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(10)
        do_wait_until(fun, deadline)
      end
    end
  end
end
