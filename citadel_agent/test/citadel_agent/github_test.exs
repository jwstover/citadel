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

    test "handles SSH URLs without .git suffix" do
      dir = setup_git_repo("git@github.com:owner/repo")
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
    setup do
      original_token = Application.get_env(:citadel_agent, :github_token)
      original_req_opts = Application.get_env(:citadel_agent, :github_req_options)

      Application.put_env(:citadel_agent, :github_token, "test-token-123")
      Application.put_env(:citadel_agent, :github_req_options, plug: {Req.Test, :github_api})

      on_exit(fn ->
        if original_token,
          do: Application.put_env(:citadel_agent, :github_token, original_token),
          else: Application.delete_env(:citadel_agent, :github_token)

        if original_req_opts,
          do: Application.put_env(:citadel_agent, :github_req_options, original_req_opts),
          else: Application.delete_env(:citadel_agent, :github_req_options)
      end)

      :ok
    end

    test "sends correct request format for draft PR" do
      test_pid = self()

      Req.Test.stub(:github_api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:github_request, conn, Jason.decode!(body)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"html_url" => "https://github.com/owner/repo/pull/1"}))
      end)

      assert {:ok, "https://github.com/owner/repo/pull/1"} =
               GitHub.create_pull_request("owner", "repo", "feature-branch", "main", "PR Title", "PR Body")

      assert_received {:github_request, conn, body}
      assert conn.method == "POST"
      assert conn.request_path == "/repos/owner/repo/pulls"
      assert body["title"] == "PR Title"
      assert body["body"] == "PR Body"
      assert body["head"] == "feature-branch"
      assert body["base"] == "main"
      assert body["draft"] == true

      [auth] = Plug.Conn.get_req_header(conn, "authorization")
      assert auth == "Bearer test-token-123"
    end

    test "returns PR URL on success" do
      Req.Test.stub(:github_api, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"html_url" => "https://github.com/o/r/pull/42"}))
      end)

      assert {:ok, "https://github.com/o/r/pull/42"} =
               GitHub.create_pull_request("o", "r", "head", "base", "Title", "Body")
    end

    test "returns error on API failure with message" do
      Req.Test.stub(:github_api, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(422, Jason.encode!(%{"message" => "Validation Failed"}))
      end)

      assert {:error, "Validation Failed"} =
               GitHub.create_pull_request("o", "r", "head", "base", "Title", "Body")
    end

    test "returns error with HTTP status when no message in response" do
      Req.Test.stub(:github_api, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{}))
      end)

      assert {:error, "HTTP 500"} =
               GitHub.create_pull_request("o", "r", "head", "base", "Title", "Body")
    end

    test "returns error when token is not configured" do
      Application.delete_env(:citadel_agent, :github_token)

      assert {:error, "GITHUB_TOKEN not configured"} =
               GitHub.create_pull_request("owner", "repo", "feature", "main", "Title", "Body")
    end
  end
end
