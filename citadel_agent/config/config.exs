import Config

config :citadel_agent,
  citadel_url: "http://localhost:4100",
  api_key: System.get_env("CITADEL_DEV_API_KEY"),
  project_path: File.cwd!(),
  poll_interval: 10_000

import_config "#{config_env()}.exs"
