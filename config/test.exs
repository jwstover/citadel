import Config
config :citadel, Oban, testing: :manual

# Use process dictionary adapter for fast, isolated feature flag tests
config :citadel, :feature_flag_adapter,
  Citadel.Settings.FeatureFlagAdapters.TestAdapter

# Disable GitHub token validation in tests (no real HTTP requests)
config :citadel, :github_token_validation, enabled: false

config :citadel, Citadel.AI,
  anthropic_api_key: "test-anthropic-key",
  openai_api_key: "test-openai-key",
  provider_overrides: %{
    anthropic: Citadel.AI.MockProvider,
    openai: Citadel.AI.MockProvider
  }

# Stripe test configuration
config :stripity_stripe,
  api_key: "sk_test_fake_key",
  signing_secret: "whsec_test_secret"

config :citadel, :stripe, publishable_key: "pk_test_fake_key"

config :citadel, Citadel.Billing,
  pro_monthly_price_id: "price_test_pro_monthly",
  pro_annual_price_id: "price_test_pro_annual",
  pro_seat_monthly_price_id: "price_test_seat_monthly",
  pro_seat_annual_price_id: "price_test_seat_annual"

config :citadel, skip_stripe_in_tests: true

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
  port: 5435,
  database: "citadel_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  # Increased for property tests which create many records concurrently
  pool_size: max(System.schedulers_online() * 4, 32),
  ownership_timeout: 120_000,
  # Increased from default 15s to handle concurrent test contention
  checkout_timeout: 30_000,
  queue_target: 5000,
  queue_interval: 10_000

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
