defmodule CitadelWeb.Plugs.CacheBodyReader do
  @moduledoc """
  A custom body reader that caches the raw request body.

  This is required for Stripe webhook signature verification, which needs
  access to the raw (unparsed) request body to verify the HMAC signature.

  ## Usage

  Configure in `endpoint.ex`:

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        body_reader: {CitadelWeb.Plugs.CacheBodyReader, :read_body, []},
        json_decoder: Phoenix.json_library()

  Then access the raw body in your controller:

      raw_body = conn.assigns[:raw_body]
  """

  @doc """
  Reads the request body and caches it in conn.assigns[:raw_body].

  The body is read in chunks and concatenated. This function is designed
  to be used as the `:body_reader` option for `Plug.Parsers`.
  """
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = update_in(conn.assigns[:raw_body], &((&1 || "") <> body))
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = update_in(conn.assigns[:raw_body], &((&1 || "") <> body))
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
