defmodule CitadelAgent.RunnerPRTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    project_path = Path.join(tmp_dir, "project")
    File.mkdir_p!(project_path)

    System.cmd("git", ["init", "-b", "main"], cd: project_path)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: project_path)
    System.cmd("git", ["config", "user.name", "Test"], cd: project_path)

    File.write!(Path.join(project_path, "README.md"), "# Test")
    System.cmd("git", ["add", "."], cd: project_path)
    System.cmd("git", ["commit", "-m", "initial"], cd: project_path)

    bare_path = Path.join(tmp_dir, "remote.git")
    System.cmd("git", ["init", "--bare", bare_path])

    # Use a GitHub-like URL for origin so parse_remote_url works,
    # but redirect actual git operations to the local bare repo via insteadOf
    github_url = "https://github.com/test-owner/test-repo.git"
    System.cmd("git", ["remote", "add", "origin", github_url], cd: project_path)

    System.cmd(
      "git",
      ["config", "url.#{bare_path}.insteadOf", github_url],
      cd: project_path
    )

    System.cmd("git", ["push", "-u", "origin", "main"], cd: project_path)

    # Mock claude script
    script_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(script_dir)
    script_path = Path.join(script_dir, "claude")

    File.write!(script_path, """
    #!/bin/bash
    if echo "$@" | grep -q "\\-\\-model"; then
      # Commit run or PR description run
      git add -A 2>/dev/null
      git commit -m "automated commit" --allow-empty-message 2>/dev/null || true
      git push -u origin HEAD 2>&1 || true
      exit 0
    else
      # Main run - produce unique content per invocation
      echo "subtask content $$" > "task_output_$$.txt"
      exit 0
    fi
    """)

    File.chmod!(script_path, 0o755)

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{script_dir}:#{original_path}")

    # Configure GitHub token and Req.Test stub
    original_token = Application.get_env(:citadel_agent, :github_token)
    original_req_opts = Application.get_env(:citadel_agent, :github_req_options)

    Application.put_env(:citadel_agent, :github_token, "test-token")
    Application.put_env(:citadel_agent, :github_req_options, plug: {Req.Test, :github_pr})

    on_exit(fn ->
      System.put_env("PATH", original_path)

      if original_token,
        do: Application.put_env(:citadel_agent, :github_token, original_token),
        else: Application.delete_env(:citadel_agent, :github_token)

      if original_req_opts,
        do: Application.put_env(:citadel_agent, :github_req_options, original_req_opts),
        else: Application.delete_env(:citadel_agent, :github_req_options)
    end)

    {:ok, project_path: project_path, bare_path: bare_path}
  end

  describe "PR creation on feature branch" do
    test "creates draft PR after merge into feature branch", %{project_path: project_path} do
      test_pid = self()

      Req.Test.stub(:github_pr, fn conn ->
        case conn.method do
          "GET" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!([]))

          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            send(test_pid, {:pr_created, conn, Jason.decode!(body)})

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(
              201,
              Jason.encode!(%{"html_url" => "https://github.com/test-owner/test-repo/pull/1"})
            )
        end
      end)

      task = %{
        "human_id" => "P-201",
        "title" => "Subtask",
        "description" => "A subtask",
        "parent_human_id" => "P-200"
      }

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)
      assert result.status == "completed"

      assert_received {:pr_created, conn, body}
      assert conn.method == "POST"
      assert conn.request_path == "/repos/test-owner/test-repo/pulls"
      assert body["draft"] == true
      assert body["head"] == "citadel/feature/P-200"
      assert body["base"] == "main"
      assert body["title"] == "P-200"
    end

    test "does not create duplicate PR for second subtask with same parent", %{
      project_path: project_path
    } do
      test_pid = self()
      pr_create_count = :counters.new(1, [:atomics])

      Req.Test.stub(:github_pr, fn conn ->
        case conn.method do
          "GET" ->
            # After first PR creation, return the existing PR
            if :counters.get(pr_create_count, 1) > 0 do
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                200,
                Jason.encode!([
                  %{"html_url" => "https://github.com/test-owner/test-repo/pull/1"}
                ])
              )
            else
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(200, Jason.encode!([]))
            end

          "POST" ->
            :counters.add(pr_create_count, 1, 1)
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            send(test_pid, {:pr_created, Jason.decode!(body)})

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(
              201,
              Jason.encode!(%{"html_url" => "https://github.com/test-owner/test-repo/pull/1"})
            )
        end
      end)

      task1 = %{
        "human_id" => "P-211",
        "title" => "First subtask",
        "description" => "First",
        "parent_human_id" => "P-210"
      }

      task2 = %{
        "human_id" => "P-212",
        "title" => "Second subtask",
        "description" => "Second",
        "parent_human_id" => "P-210"
      }

      assert {:ok, _} = CitadelAgent.Runner.execute(task1, project_path)
      assert {:ok, _} = CitadelAgent.Runner.execute(task2, project_path)

      assert :counters.get(pr_create_count, 1) == 1
    end

    test "PR creation failure does not fail the overall task", %{project_path: project_path} do
      Req.Test.stub(:github_pr, fn conn ->
        case conn.method do
          "GET" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!([]))

          "POST" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(403, Jason.encode!(%{"message" => "Forbidden"}))
        end
      end)

      task = %{
        "human_id" => "P-221",
        "title" => "Subtask",
        "description" => "A subtask",
        "parent_human_id" => "P-220"
      }

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)
      assert result.status == "completed"
    end

    test "standalone task creates PR from task branch", %{project_path: project_path} do
      test_pid = self()

      Req.Test.stub(:github_pr, fn conn ->
        case conn.method do
          "GET" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!([]))

          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            send(test_pid, {:pr_created, Jason.decode!(body)})

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(
              201,
              Jason.encode!(%{"html_url" => "https://github.com/test-owner/test-repo/pull/1"})
            )
        end
      end)

      task = %{
        "human_id" => "P-230",
        "title" => "Standalone task",
        "description" => "No parent"
      }

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)
      assert result.status == "completed"

      assert_received {:pr_created, body}
      assert body["head"] == "citadel/task-P-230"
      assert body["base"] == "main"
    end
  end
end
