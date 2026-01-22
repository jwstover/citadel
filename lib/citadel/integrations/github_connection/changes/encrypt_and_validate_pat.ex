defmodule Citadel.Integrations.GitHubConnection.Changes.EncryptAndValidatePat do
  @moduledoc """
  Validates and encrypts the GitHub PAT argument.

  Before storing the token, validates it by making a request to GitHub's API.
  If valid, stores the encrypted token and caches the GitHub username.
  If invalid, adds an error to the changeset.

  Token validation can be disabled in test environments via config:

      config :citadel, :github_token_validation, enabled: false
  """
  use Ash.Resource.Change

  alias Citadel.Integrations.GitHub

  def change(changeset, _opts, _context) do
    pat = Ash.Changeset.get_argument(changeset, :pat)

    if pat do
      validate_and_set_token(changeset, pat)
    else
      changeset
    end
  end

  defp validate_and_set_token(changeset, pat) do
    if validation_enabled?() do
      case GitHub.validate_token(pat) do
        {:ok, %{login: username}} ->
          changeset
          |> Ash.Changeset.force_change_attribute(:pat_encrypted, pat)
          |> Ash.Changeset.force_change_attribute(:github_username, username)

        {:error, :invalid_token} ->
          Ash.Changeset.add_error(changeset, field: :pat, message: "Invalid GitHub token")

        {:error, :forbidden} ->
          Ash.Changeset.add_error(changeset,
            field: :pat,
            message: "Token lacks required permissions"
          )

        {:error, {:request_failed, _reason}} ->
          Ash.Changeset.add_error(changeset,
            field: :pat,
            message: "Unable to validate token. Please try again."
          )

        {:error, _reason} ->
          Ash.Changeset.add_error(changeset,
            field: :pat,
            message: "Failed to validate GitHub token"
          )
      end
    else
      Ash.Changeset.force_change_attribute(changeset, :pat_encrypted, pat)
    end
  end

  defp validation_enabled? do
    Application.get_env(:citadel, :github_token_validation, [])
    |> Keyword.get(:enabled, true)
  end
end
