defmodule Citadel.Observability.SentryFilter do
  @moduledoc """
  `before_send` callback for Sentry. Drops known-noisy errors and scrubs
  sensitive headers/cookies before events are shipped.

  Configured via `config :sentry, before_send: {__MODULE__, :before_send}` in
  `config/runtime.exs`.
  """

  @sensitive_headers ~w(authorization cookie x-api-key x-csrf-token set-cookie)
  @dropped_exceptions [
    "Phoenix.Router.NoRouteError",
    "Plug.Parsers.ParseError"
  ]

  def before_send(%Sentry.Event{} = event) do
    if drop?(event), do: nil, else: scrub(event)
  end

  defp drop?(%Sentry.Event{exception: [%{type: type} | _]}) when type in @dropped_exceptions,
    do: true

  defp drop?(_), do: false

  defp scrub(%Sentry.Event{request: %{} = request} = event) do
    %{event | request: scrub_request(request)}
  end

  defp scrub(event), do: event

  defp scrub_request(request) do
    headers =
      request
      |> Map.get(:headers, %{})
      |> Map.new(fn {k, v} ->
        if String.downcase(to_string(k)) in @sensitive_headers do
          {k, "[Filtered]"}
        else
          {k, v}
        end
      end)

    request
    |> Map.put(:headers, headers)
    |> Map.put(:cookies, %{})
  end
end
