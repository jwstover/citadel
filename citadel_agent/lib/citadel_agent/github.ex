defmodule CitadelAgent.GitHub do
  require Logger

  @github_api "https://api.github.com"

  def create_pull_request(owner, repo, head, base, title, body) do
    token = CitadelAgent.config(:github_token)

    unless token do
      {:error, "GITHUB_TOKEN not configured"}
    else
      url = "#{@github_api}/repos/#{owner}/#{repo}/pulls"

      opts =
        Keyword.merge(
          [
            json: %{title: title, body: body, head: head, base: base, draft: true},
            headers: [
              {"authorization", "Bearer #{token}"},
              {"accept", "application/vnd.github+v3+json"}
            ]
          ],
          req_options()
        )

      case Req.post(url, opts) do
        {:ok, %Req.Response{status: status, body: body}} when status in [201] ->
          {:ok, body["html_url"]}

        {:ok, %Req.Response{status: status, body: body}} ->
          message = body["message"] || "HTTP #{status}"
          Logger.warning("GitHub API error: #{status} - #{message}")
          {:error, message}

        {:error, exception} ->
          Logger.warning("GitHub API request failed: #{Exception.message(exception)}")
          {:error, Exception.message(exception)}
      end
    end
  end

  def parse_remote_url(project_path) do
    case System.cmd("git", ["config", "--get", "remote.origin.url"],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {url, 0} ->
        url = String.trim(url)
        parse_url(url)

      {output, _code} ->
        {:error, "Failed to get remote URL: #{String.trim(output)}"}
    end
  end

  defp req_options do
    Application.get_env(:citadel_agent, :github_req_options, [])
  end

  defp parse_url("git@github.com:" <> rest) do
    extract_owner_repo(rest)
  end

  defp parse_url("https://github.com/" <> rest) do
    extract_owner_repo(rest)
  end

  defp parse_url(url) do
    {:error, "Unrecognized remote URL format: #{url}"}
  end

  defp extract_owner_repo(path) do
    path = String.trim_trailing(path, ".git")

    case String.split(path, "/", parts: 2) do
      [owner, repo] when owner != "" and repo != "" ->
        {:ok, {owner, repo}}

      _ ->
        {:error, "Could not extract owner/repo from: #{path}"}
    end
  end
end
