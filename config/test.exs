import Config
config :citadel, Oban, testing: :manual

config :citadel,
  token_signing_secret: "Lu32ul4hfEE2x/l+8SkesaKOI8zopO/1",
  google_client_id: "test-client-id",
  google_client_secret: "test-client-secret",
  google_redirect_uri: "http://localhost:4002/auth/user/google/callback"

config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :citadel, Citadel.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "citadel_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :citadel, CitadelWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ibfuXOW0otIRMtK5+06p4WWAO9ab0nb4yn2Rzx1MChZXIDFNCy1P9HyzVuMM+SdF",
  server: false

# In test we don't send emails
config :citadel, Citadel.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
