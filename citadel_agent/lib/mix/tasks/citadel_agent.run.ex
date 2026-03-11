defmodule Mix.Tasks.CitadelAgent.Run do
  @moduledoc """
  Starts the CitadelAgent worker that polls Citadel for tasks.

  ## Usage

      CITADEL_API_KEY=your_key CITADEL_PROJECT_PATH=/path/to/project mix citadel_agent.run

  ## Environment Variables

    * `CITADEL_URL` - Citadel base URL (default: http://localhost:4000)
    * `CITADEL_API_KEY` - API key for authentication (required)
    * `CITADEL_PROJECT_PATH` - Path to the project directory (required)
    * `CITADEL_POLL_INTERVAL` - Poll interval in ms (default: 10000)
  """

  use Mix.Task

  @shortdoc "Start the CitadelAgent worker"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    unless CitadelAgent.config(:api_key) do
      Mix.raise("CITADEL_API_KEY is required. Set it via environment variable or config.")
    end

    unless CitadelAgent.config(:project_path) do
      Mix.raise("CITADEL_PROJECT_PATH is required. Set it via environment variable or config.")
    end

    unless Process.whereis(CitadelAgent.Worker) do
      CitadelAgent.Worker.start_link()
    end

    Mix.shell().info("CitadelAgent is running. Press Ctrl+C to stop.")

    Process.sleep(:infinity)
  end
end
