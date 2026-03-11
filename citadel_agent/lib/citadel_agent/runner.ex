defmodule CitadelAgent.Runner do
  @moduledoc """
  Orchestrates task execution: creates an isolated git worktree, invokes Claude Code CLI,
  captures output and git diff, returns structured results. Cleans up the worktree on completion.
  """

  require Logger

  def execute(task, project_path) do
    human_id = task["human_id"]
    branch_name = "citadel/task-#{human_id}"
    worktree_path = Path.join(project_path, ".worktrees/task-#{human_id}")

    with :ok <- create_worktree(worktree_path, branch_name, project_path) do
      try do
        with {:ok, claude_result} <- run_claude(task, worktree_path),
             {:ok, diff} <- capture_diff(worktree_path) do
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
      after
        cleanup_worktree(worktree_path, branch_name, project_path)
      end
    end
  end

  defp create_worktree(worktree_path, branch_name, project_path) do
    if File.dir?(worktree_path) do
      Logger.warning("Worktree already exists at #{worktree_path}, removing stale worktree")
      remove_worktree(worktree_path, project_path)
    end

    case System.cmd(
           "git",
           ["worktree", "add", worktree_path, "-b", branch_name],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Created worktree at #{worktree_path} on branch #{branch_name}")
        :ok

      {_output, _code} ->
        case System.cmd(
               "git",
               ["worktree", "add", worktree_path, branch_name],
               cd: project_path,
               stderr_to_stdout: true
             ) do
          {_output, 0} ->
            Logger.info(
              "Created worktree at #{worktree_path} using existing branch #{branch_name}"
            )

            :ok

          {output, _code} ->
            {:error, "Failed to create worktree for #{branch_name}: #{output}"}
        end
    end
  end

  defp cleanup_worktree(worktree_path, branch_name, project_path) do
    has_commits = has_commits_on_branch?(branch_name, project_path)
    remove_worktree(worktree_path, project_path)

    unless has_commits do
      Logger.info("No commits on #{branch_name}, deleting branch")
      System.cmd("git", ["branch", "-D", branch_name], cd: project_path, stderr_to_stdout: true)
    end
  end

  defp has_commits_on_branch?(branch_name, project_path) do
    case System.cmd(
           "git",
           ["log", "HEAD..#{branch_name}", "--oneline"],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {output, 0} -> String.trim(output) != ""
      _ -> false
    end
  end

  defp remove_worktree(worktree_path, project_path) do
    case System.cmd(
           "git",
           ["worktree", "remove", worktree_path, "--force"],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Removed worktree at #{worktree_path}")

      {output, _code} ->
        Logger.warning("Failed to remove worktree at #{worktree_path}: #{output}")

        if File.dir?(worktree_path) do
          File.rm_rf!(worktree_path)
          System.cmd("git", ["worktree", "prune"], cd: project_path, stderr_to_stdout: true)
          Logger.info("Force-cleaned worktree directory and pruned")
        end
    end
  end

  defp run_claude(task, worktree_path) do
    prompt = build_prompt(task)

    Logger.info("Executing Claude Code CLI for task #{task["human_id"]}")

    claude_path = System.find_executable("claude")

    unless claude_path do
      {:error, "Claude Code CLI not found in PATH"}
    else
      port =
        Port.open(
          {:spawn,
           "#{claude_path} -p #{escape_shell(prompt)} --output-format stream-json --verbose --dangerously-skip-permissions < /dev/null 2>&1"},
          [:binary, :exit_status, cd: worktree_path]
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

  defp capture_diff(worktree_path) do
    case System.cmd("git", ["diff", "HEAD"], cd: worktree_path, stderr_to_stdout: true) do
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
