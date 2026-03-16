defmodule CitadelAgent.RunnerFeatureBranchTest do
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
      git add -A
      git commit -m "automated commit" --allow-empty-message 2>/dev/null || true
      git push -u origin HEAD 2>&1
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

    on_exit(fn ->
      System.put_env("PATH", original_path)
    end)

    {:ok, project_path: project_path, bare_path: bare_path, control_dir: control_dir}
  end

  describe "subtask branching" do
    test "subtask branches from feature branch, not main", %{
      project_path: project_path,
      bare_path: bare_path
    } do
      task = %{
        "human_id" => "P-11",
        "title" => "Subtask",
        "description" => "A subtask",
        "parent_human_id" => "P-10"
      }

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)
      assert result.status == "completed"

      # Feature branch should have been created
      {branches, 0} = System.cmd("git", ["branch"], cd: project_path)
      assert branches =~ "citadel/feature/P-10"

      # Subtask branch should exist on remote
      {log, 0} =
        System.cmd("git", ["log", "--oneline", "citadel/task-P-11"],
          cd: bare_path,
          stderr_to_stdout: true
        )

      assert log =~ "automated commit"

      # The subtask branch should be based on the feature branch, not main directly
      # Verify by checking that the feature branch is an ancestor of the task branch
      {_, exit_code} =
        System.cmd(
          "git",
          ["merge-base", "--is-ancestor", "citadel/feature/P-10", "citadel/task-P-11"],
          cd: project_path,
          stderr_to_stdout: true
        )

      assert exit_code == 0
    end

    test "feature branch is lazily created from main", %{project_path: project_path} do
      # Verify feature branch doesn't exist yet
      {branches, 0} = System.cmd("git", ["branch"], cd: project_path)
      refute branches =~ "citadel/feature/P-20"

      task = %{
        "human_id" => "P-21",
        "title" => "Subtask",
        "description" => "A subtask",
        "parent_human_id" => "P-20"
      }

      assert {:ok, _result} = CitadelAgent.Runner.execute(task, project_path)

      # Feature branch should now exist
      {branches, 0} = System.cmd("git", ["branch"], cd: project_path)
      assert branches =~ "citadel/feature/P-20"

      # Feature branch should be rooted from main (main is an ancestor)
      {_, exit_code} =
        System.cmd(
          "git",
          ["merge-base", "--is-ancestor", "main", "citadel/feature/P-20"],
          cd: project_path,
          stderr_to_stdout: true
        )

      assert exit_code == 0
    end

    test "feature branch is reused across subtasks", %{project_path: project_path} do
      task1 = %{
        "human_id" => "P-31",
        "title" => "First subtask",
        "description" => "First",
        "parent_human_id" => "P-30"
      }

      task2 = %{
        "human_id" => "P-32",
        "title" => "Second subtask",
        "description" => "Second",
        "parent_human_id" => "P-30"
      }

      assert {:ok, _} = CitadelAgent.Runner.execute(task1, project_path)
      assert {:ok, _} = CitadelAgent.Runner.execute(task2, project_path)

      # Both subtask branches should have been merged into the feature branch
      {_, exit1} =
        System.cmd(
          "git",
          ["merge-base", "--is-ancestor", "citadel/task-P-31", "citadel/feature/P-30"],
          cd: project_path,
          stderr_to_stdout: true
        )

      {_, exit2} =
        System.cmd(
          "git",
          ["merge-base", "--is-ancestor", "citadel/task-P-32", "citadel/feature/P-30"],
          cd: project_path,
          stderr_to_stdout: true
        )

      assert exit1 == 0
      assert exit2 == 0
    end

    test "standalone task still branches from main", %{project_path: project_path} do
      task = %{
        "human_id" => "P-40",
        "title" => "Standalone task",
        "description" => "No parent"
      }

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)
      assert result.status == "completed"

      # No feature branch should be created
      {branches, 0} = System.cmd("git", ["branch"], cd: project_path)
      refute branches =~ "citadel/feature/"

      # Task branch should exist
      assert branches =~ "citadel/task-P-40"
    end

    test "commits are captured against feature branch for subtasks", %{project_path: project_path} do
      task = %{
        "human_id" => "P-51",
        "title" => "Subtask",
        "description" => "A subtask",
        "parent_human_id" => "P-50"
      }

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)
      assert is_list(result.commits)
      assert length(result.commits) > 0
    end
  end

  describe "auto-merge into feature branch" do
    test "subtask branch is merged into feature branch on completion", %{
      project_path: project_path,
      bare_path: bare_path
    } do
      task = %{
        "human_id" => "P-61",
        "title" => "Subtask to merge",
        "description" => "Should auto-merge",
        "parent_human_id" => "P-60"
      }

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)
      assert result.status == "completed"

      # Feature branch should contain the subtask's changes
      {log, 0} =
        System.cmd("git", ["log", "--oneline", "citadel/feature/P-60"],
          cd: project_path,
          stderr_to_stdout: true
        )

      assert log =~ "automated commit"

      # Feature branch on remote should also have the merge
      {remote_log, 0} =
        System.cmd("git", ["log", "--oneline", "citadel/feature/P-60"],
          cd: bare_path,
          stderr_to_stdout: true
        )

      assert remote_log =~ "automated commit"
    end

    test "standalone task does not attempt merge", %{project_path: project_path} do
      task = %{
        "human_id" => "P-70",
        "title" => "Standalone task",
        "description" => "No parent, no merge"
      }

      assert {:ok, result} = CitadelAgent.Runner.execute(task, project_path)
      assert result.status == "completed"

      # No feature branch should exist
      {branches, 0} = System.cmd("git", ["branch"], cd: project_path)
      refute branches =~ "citadel/feature/"
    end

    test "merge succeeds when feature branch is already checked out in main repo", %{
      project_path: project_path,
      bare_path: bare_path
    } do
      task = %{
        "human_id" => "P-91",
        "title" => "Subtask while on feature branch",
        "description" => "Should use detached worktree fallback",
        "parent_human_id" => "P-90"
      }

      # Run task once to create and populate the feature branch
      assert {:ok, _} = CitadelAgent.Runner.execute(task, project_path)

      # Now check out the feature branch in the main repo (simulates user working on it)
      System.cmd("git", ["checkout", "citadel/feature/P-90"], cd: project_path)

      # Run a second subtask — merge should still succeed via detached worktree
      task2 = %{
        "human_id" => "P-92",
        "title" => "Second subtask while checked out",
        "description" => "Detached merge",
        "parent_human_id" => "P-90"
      }

      assert {:ok, result} = CitadelAgent.Runner.execute(task2, project_path)
      assert result.status == "completed"

      # Feature branch on remote should have both subtasks' commits
      {remote_log, 0} =
        System.cmd("git", ["log", "--oneline", "citadel/feature/P-90"],
          cd: bare_path,
          stderr_to_stdout: true
        )

      assert remote_log =~ "automated commit"

      # Switch back to main to not interfere with other tests
      System.cmd("git", ["checkout", "main"], cd: project_path)
    end

    test "second subtask merge includes changes from both subtasks", %{
      project_path: project_path
    } do
      task1 = %{
        "human_id" => "P-81",
        "title" => "First subtask",
        "description" => "First",
        "parent_human_id" => "P-80"
      }

      task2 = %{
        "human_id" => "P-82",
        "title" => "Second subtask",
        "description" => "Second",
        "parent_human_id" => "P-80"
      }

      assert {:ok, _} = CitadelAgent.Runner.execute(task1, project_path)
      assert {:ok, _} = CitadelAgent.Runner.execute(task2, project_path)

      # Both subtask branches should be merged into the feature branch
      {_, exit1} =
        System.cmd(
          "git",
          ["merge-base", "--is-ancestor", "citadel/task-P-81", "citadel/feature/P-80"],
          cd: project_path,
          stderr_to_stdout: true
        )

      {_, exit2} =
        System.cmd(
          "git",
          ["merge-base", "--is-ancestor", "citadel/task-P-82", "citadel/feature/P-80"],
          cd: project_path,
          stderr_to_stdout: true
        )

      assert exit1 == 0
      assert exit2 == 0
    end
  end
end
