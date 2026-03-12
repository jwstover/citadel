import Config

config :citadel_agent,
  citadel_url: "https://citadel-floral-star-4898.fly.dev",
  api_key: System.get_env("CITADEL_AGENT_PROD_API_KEY"),
  project_path: "/Users/jacob.stover/code/personal/citadel",
  poll_interval: 10_000
