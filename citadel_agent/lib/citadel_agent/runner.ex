defmodule CitadelAgent.Runner do
  @moduledoc """
  Orchestrates task execution: creates a git branch, invokes Claude Code CLI,
  captures output and git diff, returns structured results.
  """

  require Logger

  def execute(task, project_path) do
    human_id = task["human_id"]
    branch_name = "citadel/task-#{human_id}"

    with :ok <- create_branch(branch_name, project_path),
         {:ok, claude_result} <- run_claude(task, project_path),
         {:ok, diff} <- capture_diff(project_path) do
      {:ok,
       %{
         status: determine_status(claude_result),
         diff: diff,
         logs: claude_result.output,
         test_output: nil,
         error_message: nil
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_branch(branch_name, project_path) do
    case System.cmd("git", ["checkout", "-b", branch_name],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, _code} ->
        case System.cmd("git", ["checkout", branch_name],
               cd: project_path,
               stderr_to_stdout: true
             ) do
          {_output, 0} ->
            :ok

          {_, _} ->
            {:error, "Failed to create or checkout branch #{branch_name}: #{output}"}
        end
    end
  end

  defp run_claude(task, project_path) do
    prompt = build_prompt(task)

    Logger.info("Executing Claude Code CLI for task #{task["human_id"]}")

    claude_path = System.find_executable("claude")

    unless claude_path do
      {:error, "Claude Code CLI not found in PATH"}
    else
      port =
        Port.open(
          {:spawn, "#{claude_path} -p #{escape_shell(prompt)} --output-format stream-json --verbose --dangerously-skip-permissions < /dev/null 2>&1"},
          [:binary, :exit_status, cd: project_path]
        )

      collect_port_output(port, task["human_id"], [])
    end
  end

  defp collect_port_output(port, human_id, acc) do
    receive do
      {^port, {:data, data}} ->
        for line <- String.split(data, "\n", trim: true) do
          Logger.info("[claude:#{human_id}] #{line}")
        end

        collect_port_output(port, human_id, [data | acc])

      {^port, {:exit_status, code}} ->
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        {:ok, %{exit_code: code, output: output}}
    end
  end

  defp build_prompt(task) do
    title = task["title"] || ""
    description = task["description"] || ""

    """
    Task: #{title}

    #{description}
    """
    |> String.trim()
  end

  defp capture_diff(project_path) do
    case System.cmd("git", ["diff", "HEAD"], cd: project_path, stderr_to_stdout: true) do
      {diff, 0} ->
        {:ok, diff}

      {output, _code} ->
        {:ok, output}
    end
  end

  defp escape_shell(str) do
    "'" <> String.replace(str, "'", "'\\''") <> "'"
  end

  defp determine_status(%{exit_code: 0}), do: "completed"
  defp determine_status(_), do: "failed"
end
