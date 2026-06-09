import Config

config :citadel_agent,
  poll_interval: 10_000

import_config "#{config_env()}.exs"
