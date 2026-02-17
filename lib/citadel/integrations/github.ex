defmodule Citadel.Integrations.GitHub do
  @moduledoc """
  GitHub API client for token validation and user info retrieval.
  """

  @github_api_url "https://api.github.com"
  @user_agent "Citadel"

  @doc """
  Validates a GitHub Personal Access Token by making a request to the /user endpoint.

  Returns `{:ok, user_info}` with the authenticated user's information if the token is valid,
  or `{:error, reason}` if the token is invalid or the request fails.

  ## Examples

      iex> Citadel.Integrations.GitHub.validate_token("ghp_valid_token")
      {:ok, %{login: "username", id: 12345}}

      iex> Citadel.Integrations.GitHub.validate_token("invalid_token")
      {:error, :invalid_token}
  """
  def validate_token(token) when is_binary(token) and byte_size(token) > 0 do
    case make_request("/user", token) do
      {:ok, %{status: 200, body: %{"login" => login, "id" => id}}} ->
        {:ok, %{login: login, id: id}}

      {:ok, %{status: 200, body: _body}} ->
        {:error, :unexpected_response}

      {:ok, %{status: 401}} ->
        {:error, :invalid_token}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  def validate_token(_), do: {:error, :invalid_token}

  defp make_request(path, token) do
    url = @github_api_url <> path

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Accept", "application/vnd.github+json"},
      {"User-Agent", @user_agent},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, response} ->
        {:ok, %{status: response.status, body: response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
