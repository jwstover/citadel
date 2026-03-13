defmodule CitadelAgent.PreflightTest do
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

  describe "run!/0" do
    test "raises when project path is not configured" do
      original = CitadelAgent.config(:project_path)
      Application.put_env(:citadel_agent, :project_path, nil)

      assert_raise CitadelAgent.Preflight.CheckError, ~r/project path.*not configured/, fn ->
        CitadelAgent.Preflight.run!()
      end

      Application.put_env(:citadel_agent, :project_path, original)
    end

    test "raises when project path does not exist" do
      original = CitadelAgent.config(:project_path)
      Application.put_env(:citadel_agent, :project_path, "/nonexistent/path/abc123")

      assert_raise CitadelAgent.Preflight.CheckError, ~r/does not exist/, fn ->
        CitadelAgent.Preflight.run!()
      end

      Application.put_env(:citadel_agent, :project_path, original)
    end

    test "raises when project path is not a git repo" do
      non_git_dir = Path.join(System.tmp_dir!(), "citadel_test_non_git_#{System.unique_integer([:positive])}")
      File.mkdir_p!(non_git_dir)
      on_exit(fn -> File.rm_rf!(non_git_dir) end)

      original = CitadelAgent.config(:project_path)
      Application.put_env(:citadel_agent, :project_path, non_git_dir)

      assert_raise CitadelAgent.Preflight.CheckError, ~r/not a git repository/, fn ->
        CitadelAgent.Preflight.run!()
      end

      Application.put_env(:citadel_agent, :project_path, original)
    end

    test "raises when GitHub token is not configured", %{project_path: project_path} do
      original_path = CitadelAgent.config(:project_path)
      original_token = CitadelAgent.config(:github_token)
      Application.put_env(:citadel_agent, :project_path, project_path)
      Application.put_env(:citadel_agent, :github_token, nil)

      assert_raise CitadelAgent.Preflight.CheckError, ~r/GITHUB_TOKEN is not configured/, fn ->
        CitadelAgent.Preflight.run!()
      end

      Application.put_env(:citadel_agent, :project_path, original_path)
      Application.put_env(:citadel_agent, :github_token, original_token)
    end
  end
end
