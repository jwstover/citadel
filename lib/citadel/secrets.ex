defmodule Citadel.Secrets do
  @moduledoc """
  Manages secrets for AshAuthentication, providing token signing secrets and OAuth credentials.
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

  def secret_for(
        [:authentication, :strategies, :google, :client_id],
        Citadel.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:citadel, :google_client_id)
  end

  def secret_for(
        [:authentication, :strategies, :google, :client_secret],
        Citadel.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:citadel, :google_client_secret)
  end

  def secret_for(
        [:authentication, :strategies, :google, :redirect_uri],
        Citadel.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:citadel, :google_redirect_uri)
  end
end
