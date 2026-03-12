import Config

if url = System.get_env("CITADEL_URL") do
  config :citadel_agent, citadel_url: url
end

if key = System.get_env("CITADEL_API_KEY") do
  config :citadel_agent, api_key: key
end

if path = System.get_env("CITADEL_PROJECT_PATH") do
  config :citadel_agent, project_path: path
end

if interval = System.get_env("CITADEL_POLL_INTERVAL") do
  config :citadel_agent, poll_interval: String.to_integer(interval)
end

if stall_timeout = System.get_env("CITADEL_STALL_TIMEOUT") do
  config :citadel_agent, stall_timeout_ms: String.to_integer(stall_timeout)
end
