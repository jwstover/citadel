defmodule CitadelAgent.GitHubTest do
  use ExUnit.Case, async: true

  alias CitadelAgent.GitHub

  describe "parse_remote_url/1" do
    test "parses SSH remote URL" do
      dir = setup_git_repo("git@github.com:jwstover/citadel.git")
      assert {:ok, {"jwstover", "citadel"}} = GitHub.parse_remote_url(dir)
    end

    test "parses HTTPS remote URL" do
      dir = setup_git_repo("https://github.com/jwstover/citadel.git")
      assert {:ok, {"jwstover", "citadel"}} = GitHub.parse_remote_url(dir)
    end

    test "strips trailing .git" do
      dir = setup_git_repo("git@github.com:owner/repo.git")
      assert {:ok, {"owner", "repo"}} = GitHub.parse_remote_url(dir)
    end

    test "handles URLs without .git suffix" do
      dir = setup_git_repo("https://github.com/owner/repo")
      assert {:ok, {"owner", "repo"}} = GitHub.parse_remote_url(dir)
    end

    test "returns error for unrecognized format" do
      dir = setup_git_repo("https://gitlab.com/owner/repo.git")
      assert {:error, "Unrecognized remote URL format:" <> _} = GitHub.parse_remote_url(dir)
    end

    test "returns error when no remote exists" do
      dir = System.tmp_dir!() |> Path.join("github_test_no_remote_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      System.cmd("git", ["init"], cd: dir)

      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:error, _} = GitHub.parse_remote_url(dir)
    end

    defp setup_git_repo(remote_url) do
      dir = System.tmp_dir!() |> Path.join("github_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      System.cmd("git", ["init"], cd: dir)
      System.cmd("git", ["remote", "add", "origin", remote_url], cd: dir)

      on_exit(fn -> File.rm_rf!(dir) end)

      dir
    end
  end

  describe "create_pull_request/6" do
    test "returns error when token is not configured" do
      original = Application.get_env(:citadel_agent, :github_token)
      Application.delete_env(:citadel_agent, :github_token)

      on_exit(fn ->
        if original, do: Application.put_env(:citadel_agent, :github_token, original)
      end)

      assert {:error, "GITHUB_TOKEN not configured"} =
               GitHub.create_pull_request("owner", "repo", "feature", "main", "Title", "Body")
    end
  end
end
