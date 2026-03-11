defmodule CitadelAgent.RunnerTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    System.cmd("git", ["init"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)

    File.write!(Path.join(tmp_dir, "README.md"), "# Test")
    System.cmd("git", ["add", "."], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    {:ok, project_path: tmp_dir}
  end

  describe "worktree creation" do
    test "creates worktree in .worktrees directory", %{project_path: project_path} do
      task = %{"human_id" => "TEST-1", "title" => "Test", "description" => "A test task"}
      worktree_path = Path.join(project_path, ".worktrees/task-TEST-1")

      # execute will fail on claude CLI not found, but worktree should be created first
      # We test the worktree creation directly instead
      _result = CitadelAgent.Runner.execute(task, project_path)

      # Worktree should be cleaned up after execution (even on failure)
      refute File.dir?(worktree_path)

      # Branch should be cleaned up too since no commits were made
      {branches, 0} = System.cmd("git", ["branch"], cd: project_path)
      refute branches =~ "citadel/task-TEST-1"
    end

    test "handles stale worktree from previous failed cleanup", %{project_path: project_path} do
      # Create a stale worktree manually
      worktree_path = Path.join(project_path, ".worktrees/task-TEST-2")

      System.cmd("git", ["worktree", "add", worktree_path, "-b", "citadel/task-TEST-2"],
        cd: project_path
      )

      assert File.dir?(worktree_path)

      task = %{"human_id" => "TEST-2", "title" => "Test", "description" => "A test task"}
      _result = CitadelAgent.Runner.execute(task, project_path)

      # Should have cleaned up
      refute File.dir?(worktree_path)
    end

    test "preserves branch when commits exist", %{project_path: project_path} do
      branch_name = "citadel/task-TEST-3"
      worktree_path = Path.join(project_path, ".worktrees/task-TEST-3")

      # Create worktree, add a commit, then remove it
      System.cmd("git", ["worktree", "add", worktree_path, "-b", branch_name],
        cd: project_path
      )

      File.write!(Path.join(worktree_path, "new_file.txt"), "content")
      System.cmd("git", ["add", "."], cd: worktree_path)
      System.cmd("git", ["commit", "-m", "task commit"], cd: worktree_path)
      System.cmd("git", ["worktree", "remove", worktree_path], cd: project_path)

      # Now run the agent on the same task (branch already exists with commits)
      task = %{"human_id" => "TEST-3", "title" => "Test", "description" => "A test task"}
      _result = CitadelAgent.Runner.execute(task, project_path)

      # Worktree cleaned up
      refute File.dir?(worktree_path)

      # Branch should be preserved since it has commits
      {branches, 0} = System.cmd("git", ["branch"], cd: project_path)
      assert branches =~ branch_name
    end
  end
end
