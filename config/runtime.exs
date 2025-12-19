import Config

# LangChain OpenAI key configuration - allows nil for graceful degradation
config :langchain,
  openai_key: fn ->
    case System.get_env("OPENAI_API_KEY") do
      nil -> nil
      key -> key
    end
  end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/citadel start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :citadel, CitadelWeb.Endpoint, server: true
end

# Configure AI providers for chat functionality
# Set ANTHROPIC_API_KEY and/or OPENAI_API_KEY environment variables

# Anthropic (Claude) provider configuration
anthropic_api_key = System.get_env("ANTHROPIC_API_KEY")

# OpenAI (GPT) provider configuration
openai_api_key = System.get_env("OPENAI_API_KEY")

# Default provider selection (falls back to :anthropic if not set)
default_provider =
  case System.get_env("DEFAULT_AI_PROVIDER") do
    "openai" -> :openai
    "anthropic" -> :anthropic
    _ -> :anthropic
  end

# Configure Citadel.AI with provider settings
# In test mode, preserve any existing config (like provider_overrides for mocking)
if config_env() == :test do
  existing_config = Application.get_env(:citadel, Citadel.AI) || []

  config :citadel,
         Citadel.AI,
         Keyword.merge(existing_config,
           anthropic_api_key: existing_config[:anthropic_api_key] || anthropic_api_key,
           openai_api_key: existing_config[:openai_api_key] || openai_api_key,
           default_provider: existing_config[:default_provider] || default_provider
         )
else
  config :citadel, Citadel.AI,
    anthropic_api_key: anthropic_api_key,
    openai_api_key: openai_api_key,
    default_provider: default_provider
end

# Cloak encryption configuration for sensitive data (GitHub PATs, etc.)
# In dev/test, use a default key. In prod, require CLOAK_KEY env var.
cloak_key =
  if config_env() == :prod do
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      Generate one with: :crypto.strong_rand_bytes(32) |> Base.encode64()
      """
  else
    # Default key for dev/test - DO NOT use in production
    System.get_env("CLOAK_KEY") || "rkYjLw7vTj7mQxYVw8vK+KRj6bEADT5PBvxNOPkT0Oc="
  end

config :citadel, Citadel.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1", key: Base.decode64!(cloak_key), iv_length: 12
    }
  ]

# Billing configuration - Stripe price IDs for subscription plans
config :citadel, Citadel.Billing,
  pro_monthly_price_id: System.get_env("STRIPE_PRO_MONTHLY_PRICE_ID"),
  pro_annual_price_id: System.get_env("STRIPE_PRO_ANNUAL_PRICE_ID"),
  pro_seat_monthly_price_id: System.get_env("STRIPE_SEAT_MONTHLY_PRICE_ID"),
  pro_seat_annual_price_id: System.get_env("STRIPE_SEAT_ANNUAL_PRICE_ID")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :citadel, Citadel.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :citadel, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :citadel, CitadelWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :citadel,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!"),
    google_client_id:
      System.get_env("GOOGLE_CLIENT_ID") ||
        raise("Missing environment variable `GOOGLE_CLIENT_ID`!"),
    google_client_secret:
      System.get_env("GOOGLE_CLIENT_SECRET") ||
        raise("Missing environment variable `GOOGLE_CLIENT_SECRET`!"),
    google_redirect_uri:
      System.get_env("GOOGLE_REDIRECT_URI") ||
        raise("Missing environment variable `GOOGLE_REDIRECT_URI`!")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :citadel, CitadelWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :citadel, CitadelWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :citadel, Citadel.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
