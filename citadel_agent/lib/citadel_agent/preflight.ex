defmodule CitadelAgent.Preflight do
  @moduledoc """
  Validates the execution environment before the agent starts accepting work.
  Checks for required CLI tools, valid project path, and API reachability.
  """

  require Logger

  defmodule CheckError do
    defexception [:message]
  end

  def run! do
    checks = [
      {"git CLI", &check_git/0},
      {"claude CLI", &check_claude/0},
      {"claude auth", &check_claude_auth/0},
      {"project path", &check_project_path/0},
      {"Citadel API", &check_api/0}
    ]

    Enum.each(checks, fn {name, check_fn} ->
      case check_fn.() do
        :ok ->
          Logger.info("Preflight check passed: #{name}")

        {:error, reason} ->
          raise CheckError, "Preflight check failed (#{name}): #{reason}"
      end
    end)

    Logger.info("All preflight checks passed")
    :ok
  end

  defp check_claude do
    if System.find_executable("claude") do
      :ok
    else
      {:error, "claude CLI not found in PATH"}
    end
  end

  defp check_claude_auth do
    claude_path = System.find_executable("claude")

    case System.cmd(claude_path, ["auth", "status"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> Jason.decode()
        |> case do
          {:ok, %{"loggedIn" => true}} ->
            :ok

          _ ->
            {:error, "claude is not authenticated — run `claude auth login` first"}
        end

      {_output, _code} ->
        {:error, "claude is not authenticated — run `claude auth login` first"}
    end
  end

  defp check_git do
    if System.find_executable("git") do
      :ok
    else
      {:error, "git not found in PATH"}
    end
  end

  defp check_project_path do
    path = CitadelAgent.config(:project_path)

    cond do
      is_nil(path) ->
        {:error, "CITADEL_PROJECT_PATH is not configured"}

      not File.dir?(path) ->
        {:error, "project path does not exist: #{path}"}

      true ->
        case System.cmd("git", ["rev-parse", "--git-dir"], cd: path, stderr_to_stdout: true) do
          {_output, 0} ->
            :ok

          {output, _code} ->
            {:error, "project path is not a git repository: #{String.trim(output)}"}
        end
    end
  end

  defp check_api do
    case CitadelAgent.Client.fetch_next_task() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Citadel API unreachable: #{inspect(reason)}"}
    end
  end
end
