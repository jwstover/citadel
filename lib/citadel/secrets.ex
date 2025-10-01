defmodule Citadel.Secrets do
  @moduledoc """
  Manages secrets for AshAuthentication, providing token signing secrets.
  """
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Citadel.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:citadel, :token_signing_secret)
  end
end
