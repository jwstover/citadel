defmodule CitadelAgent.GitHub do
  require Logger

  @github_api "https://api.github.com"

  def find_pull_request(owner, repo, head, base) do
    token = CitadelAgent.config(:github_token)

    unless token do
      {:error, "GITHUB_TOKEN not configured"}
    else
      url = "#{@github_api}/repos/#{owner}/#{repo}/pulls"

      opts =
        Keyword.merge(
          [
            params: [head: "#{owner}:#{head}", base: base, state: "open"],
            headers: [
              {"authorization", "Bearer #{token}"},
              {"accept", "application/vnd.github+v3+json"}
            ]
          ],
          req_options()
        )

      case Req.get(url, opts) do
        {:ok, %Req.Response{status: 200, body: [pr | _]}} when is_map(pr) ->
          {:ok, pr["html_url"]}

        {:ok, %Req.Response{status: 200, body: []}} ->
          {:ok, nil}

        {:ok, %Req.Response{status: status, body: body}} when is_map(body) ->
          message = body["message"] || "HTTP #{status}"
          Logger.warning("GitHub API error checking for existing PR: #{status} - #{message}")
          {:ok, nil}

        {:ok, %Req.Response{status: status}} ->
          Logger.warning("GitHub API error checking for existing PR: HTTP #{status}")
          {:ok, nil}

        {:error, exception} ->
          Logger.warning("GitHub API request failed checking for PR: #{Exception.message(exception)}")
          {:ok, nil}
      end
    end
  end

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

        {:ok, %Req.Response{status: 422, body: body}} when is_map(body) ->
          errors = body["errors"] || []
          error_messages = Enum.map_join(errors, "; ", &(&1["message"] || inspect(&1)))
          message = body["message"] || "Validation Failed"
          Logger.warning("GitHub API error: 422 - #{message}: #{error_messages}")

          if pr_already_exists?(errors) do
            {:ok, :already_exists}
          else
            {:error, "#{message}: #{error_messages}"}
          end

        {:ok, %Req.Response{status: status, body: body}} when is_map(body) ->
          message = body["message"] || "HTTP #{status}"
          Logger.warning("GitHub API error: #{status} - #{message}")
          {:error, message}

        {:ok, %Req.Response{status: status}} ->
          Logger.warning("GitHub API error: #{status}")
          {:error, "HTTP #{status}"}

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

  defp pr_already_exists?(errors) when is_list(errors) do
    Enum.any?(errors, fn
      %{"message" => msg} when is_binary(msg) ->
        String.contains?(msg, "A pull request already exists")

      _ ->
        false
    end)
  end

  defp pr_already_exists?(_), do: false

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
