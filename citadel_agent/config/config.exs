import Config

config :citadel_agent,
  citadel_url: "http://localhost:4000",
  api_key: nil,
  project_path: nil,
  poll_interval: 10_000

import_config "#{config_env()}.exs"
