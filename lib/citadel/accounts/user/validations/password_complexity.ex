defmodule Citadel.Accounts.User.Validations.PasswordComplexity do
  @moduledoc """
  Validates password complexity requirements.

  Requirements:
  - At least 8 characters
  - At least one uppercase letter
  - At least one lowercase letter
  - At least one number
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def validate(changeset, opts, _context) do
    password_field = Keyword.get(opts, :attribute, :password)

    case Ash.Changeset.get_argument(changeset, password_field) do
      nil ->
        :ok

      password ->
        validate_password(password)
    end
  end

  defp validate_password(password) do
    cond do
      String.length(password) < 8 ->
        {:error, field: :password, message: "must be at least 8 characters"}

      not Regex.match?(~r/[A-Z]/, password) ->
        {:error, field: :password, message: "must contain at least one uppercase letter"}

      not Regex.match?(~r/[a-z]/, password) ->
        {:error, field: :password, message: "must contain at least one lowercase letter"}

      not Regex.match?(~r/[0-9]/, password) ->
        {:error, field: :password, message: "must contain at least one number"}

      true ->
        :ok
    end
  end
end
