defmodule CitadelAgent.RunnerCommitTest do
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
    System.cmd("git", ["remote", "add", "origin", bare_path], cd: project_path)
    System.cmd("git", ["push", "-u", "origin", "main"], cd: project_path)

    control_dir = Path.join(tmp_dir, "control")
    File.mkdir_p!(control_dir)

    script_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(script_dir)
    script_path = Path.join(script_dir, "claude")

    File.write!(script_path, """
    #!/bin/bash
    CONTROL_DIR="#{control_dir}"

    if echo "$@" | grep -q "\\-\\-model"; then
      # Commit run
      if [ -f "$CONTROL_DIR/fail_commit" ]; then
        echo "commit failed"
        exit 1
      fi
      git add -A
      git commit -m "automated commit" --allow-empty-message 2>/dev/null || true
      git push -u origin HEAD 2>&1
      exit 0
    else
      # Main run
      if [ -f "$CONTROL_DIR/fail_main" ]; then
        echo "main run failed"
        exit 1
      fi
      echo "new content" > task_output.txt
      exit 0
    fi
    """)

    File.chmod!(script_path, 0o755)

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{script_dir}:#{original_path}")

    on_exit(fn ->
      System.put_env("PATH", original_path)
    end)

    {:ok, project_path: project_path, bare_path: bare_path, control_dir: control_dir}
  end

  describe "commit and push" do
    test "successful run commits changes and pushes to remote", %{
      project_path: project_path,
      bare_path: bare_path
    } do
      task = %{"human_id" => "CP-1", "title" => "Test task", "description" => "A test task"}

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)
      assert result.status == "completed"
      assert is_list(result.commits)
      assert length(result.commits) > 0

      {log, 0} =
        System.cmd("git", ["log", "--oneline", "citadel/task-CP-1"],
          cd: bare_path,
          stderr_to_stdout: true
        )

      assert log =~ "automated commit"
    end

    test "failed main run skips commit step", %{
      project_path: project_path,
      bare_path: bare_path,
      control_dir: control_dir
    } do
      File.write!(Path.join(control_dir, "fail_main"), "")

      task = %{"human_id" => "CP-2", "title" => "Test task", "description" => "A test task"}

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)
      assert result.status == "failed"

      {branches, _} =
        System.cmd("git", ["branch", "-r"], cd: bare_path, stderr_to_stdout: true)

      refute branches =~ "citadel/task-CP-2"
    end

    test "failed commit step returns error", %{
      project_path: project_path,
      control_dir: control_dir
    } do
      File.write!(Path.join(control_dir, "fail_commit"), "")

      task = %{"human_id" => "CP-3", "title" => "Test task", "description" => "A test task"}

      assert {:error, reason} = CitadelAgent.Runner.execute(task, project_path)
      assert reason =~ "Commit step failed"
    end

    test "capture_commits returns commit SHAs from worktree", %{project_path: project_path} do
      task = %{"human_id" => "CP-4", "title" => "Test task", "description" => "A test task"}

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)

      assert is_list(result.commits)
      assert length(result.commits) > 0
      assert Enum.all?(result.commits, &Regex.match?(~r/^[0-9a-f]{40}$/, &1))
    end
  end
end
