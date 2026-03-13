defmodule CitadelAgent.Runner do
  @moduledoc """
  Orchestrates task execution: creates an isolated git worktree, invokes Claude Code CLI,
  captures output and git diff, returns structured results. Cleans up the worktree on completion.

  Includes stall detection: if the Claude Code process exceeds the configured timeout,
  it is killed and the run is marked as failed.
  """

  require Logger

  @default_stall_timeout 600_000

  @commit_stall_timeout 120_000

  def execute(task, project_path) do
    human_id = task["human_id"]
    branch_name = "citadel/task-#{human_id}"
    worktree_path = Path.join(project_path, ".worktrees/task-#{human_id}")
    base_branch = base_branch_for(task)

    with :ok <- fetch_origin(project_path),
         :ok <- maybe_ensure_feature_branch(task, project_path),
         :ok <- create_worktree(worktree_path, branch_name, base_branch, project_path) do
      result =
        try do
          with {:ok, claude_result} <- run_claude(task, worktree_path),
               :ok <- maybe_commit_and_push(claude_result, task, worktree_path, branch_name),
               {:ok, diff} <- capture_diff(worktree_path, base_branch, branch_name) do
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
          cleanup_worktree(worktree_path, branch_name, base_branch, project_path)
        end

      case result do
        {:ok, %{status: "completed"}} ->
          maybe_merge_into_feature_branch(task, branch_name, project_path)
          result

        _ ->
          result
      end
    end
  end

  defp maybe_merge_into_feature_branch(%{"parent_human_id" => parent_id} = _task, task_branch, project_path)
       when is_binary(parent_id) do
    feature_branch = "citadel/feature/#{parent_id}"
    merge_into_feature_branch(task_branch, feature_branch, project_path)
  end

  defp maybe_merge_into_feature_branch(_task, _task_branch, _project_path), do: :ok

  defp merge_into_feature_branch(task_branch, feature_branch, project_path) do
    merge_id = System.unique_integer([:positive])
    merge_worktree = Path.join(project_path, ".worktrees/merge-#{merge_id}")

    try do
      case System.cmd("git", ["worktree", "add", merge_worktree, feature_branch],
             cd: project_path,
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          case System.cmd("git", ["merge", task_branch, "--no-edit"],
                 cd: merge_worktree,
                 stderr_to_stdout: true
               ) do
            {_output, 0} ->
              case System.cmd("git", ["push", "origin", feature_branch],
                     cd: merge_worktree,
                     stderr_to_stdout: true
                   ) do
                {_output, 0} ->
                  Logger.info("Merged #{task_branch} into #{feature_branch} and pushed")
                  :ok

                {output, _code} ->
                  Logger.warning("Failed to push #{feature_branch} after merge: #{output}")
                  :ok
              end

            {output, _code} ->
              System.cmd("git", ["merge", "--abort"],
                cd: merge_worktree,
                stderr_to_stdout: true
              )

              Logger.warning(
                "Merge conflict merging #{task_branch} into #{feature_branch}: #{String.slice(output, 0, 500)}"
              )

              :ok
          end

        {output, _code} ->
          Logger.warning("Failed to create merge worktree for #{feature_branch}: #{output}")
          :ok
      end
    after
      remove_worktree(merge_worktree, project_path)
    end
  end

  defp fetch_origin(project_path) do
    case System.cmd("git", ["fetch", "origin"],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Fetched latest from origin")
        :ok

      {output, _code} ->
        {:error, "Failed to fetch from origin: #{output}"}
    end
  end

  defp base_branch_for(%{"parent_human_id" => parent_id}) when is_binary(parent_id) do
    "citadel/feature/#{parent_id}"
  end

  defp base_branch_for(_task), do: "origin/main"

  defp maybe_ensure_feature_branch(%{"parent_human_id" => parent_id}, project_path)
       when is_binary(parent_id) do
    ensure_feature_branch("citadel/feature/#{parent_id}", project_path)
  end

  defp maybe_ensure_feature_branch(_task, _project_path), do: :ok

  defp ensure_feature_branch(feature_branch, project_path) do
    local_exists? = branch_exists_locally?(feature_branch, project_path)
    remote_exists? = branch_exists_on_remote?(feature_branch, project_path)

    cond do
      local_exists? and remote_exists? ->
        fetch_and_update_branch(feature_branch, project_path)

      local_exists? ->
        :ok

      remote_exists? ->
        System.cmd(
          "git",
          ["branch", feature_branch, "origin/#{feature_branch}"],
          cd: project_path,
          stderr_to_stdout: true
        )

        :ok

      true ->
        case System.cmd(
               "git",
               ["branch", feature_branch, "origin/main"],
               cd: project_path,
               stderr_to_stdout: true
             ) do
          {_output, 0} ->
            Logger.info("Created feature branch #{feature_branch} from origin/main")
            :ok

          {output, _code} ->
            {:error, "Failed to create feature branch #{feature_branch}: #{output}"}
        end
    end
  end

  defp branch_exists_locally?(branch, project_path) do
    case System.cmd("git", ["branch", "--list", branch], cd: project_path, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output) != ""
      _ -> false
    end
  end

  defp branch_exists_on_remote?(branch, project_path) do
    case System.cmd("git", ["ls-remote", "--heads", "origin", branch],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {output, 0} -> String.trim(output) != ""
      _ -> false
    end
  end

  defp fetch_and_update_branch(branch, project_path) do
    System.cmd("git", ["fetch", "origin", branch], cd: project_path, stderr_to_stdout: true)

    System.cmd("git", ["update-ref", "refs/heads/#{branch}", "origin/#{branch}"],
      cd: project_path,
      stderr_to_stdout: true
    )

    :ok
  end

  defp create_worktree(worktree_path, branch_name, base_branch, project_path) do
    if File.dir?(worktree_path) do
      Logger.warning("Worktree already exists at #{worktree_path}, removing stale worktree")
      remove_worktree(worktree_path, project_path)
    end

    case System.cmd(
           "git",
           ["worktree", "add", worktree_path, "-b", branch_name, base_branch],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Created worktree at #{worktree_path} on branch #{branch_name} from #{base_branch}")
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

  defp cleanup_worktree(worktree_path, branch_name, base_branch, project_path) do
    has_commits = has_commits_on_branch?(branch_name, base_branch, project_path)
    remove_worktree(worktree_path, project_path)

    unless has_commits do
      Logger.info("No commits on #{branch_name}, deleting branch")
      System.cmd("git", ["branch", "-D", branch_name], cd: project_path, stderr_to_stdout: true)
    end
  rescue
    exception ->
      Logger.error(
        "Worktree cleanup failed: #{Exception.format(:error, exception, __STACKTRACE__)}"
      )
  end

  defp has_commits_on_branch?(branch_name, base_branch, project_path) do
    case System.cmd(
           "git",
           ["log", "#{base_branch}..#{branch_name}", "--oneline"],
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
          case File.rm_rf(worktree_path) do
            {:ok, _} ->
              System.cmd("git", ["worktree", "prune"],
                cd: project_path,
                stderr_to_stdout: true
              )

              Logger.info("Force-cleaned worktree directory and pruned")

            {:error, reason, path} ->
              Logger.error(
                "Failed to force-clean worktree directory #{path}: #{inspect(reason)}, pruning anyway"
              )

              System.cmd("git", ["worktree", "prune"],
                cd: project_path,
                stderr_to_stdout: true
              )
          end
        end
    end
  end

  defp maybe_commit_and_push(%{exit_code: 0}, task, worktree_path, branch_name) do
    task_context = build_prompt(task)

    prompt = """
    You are a git commit assistant. Review the uncommitted changes and create well-structured commits.

    ## Task Context
    #{task_context}

    ## Instructions
    1. Run `git diff` to review all changes
    2. Stage and commit changes with clear, descriptive commit messages that explain the "why" not just the "what"
    3. If changes span multiple logical concerns, split them into separate commits
    4. Push the branch to remote: `git push -u origin #{branch_name}`
    5. Do NOT modify any files. Only use git commands to stage, commit, and push.
    6. If there are no uncommitted changes, just push any existing commits to the remote.
    """

    case run_claude_cli(prompt,
           working_dir: worktree_path,
           label: "commit:#{task["human_id"]}",
           timeout: @commit_stall_timeout,
           model: "sonnet"
         ) do
      {:ok, %{exit_code: 0}} ->
        :ok

      {:ok, %{exit_code: code, output: output}} ->
        {:error, "Commit step failed (exit code #{code}): #{String.slice(output, 0, 500)}"}

      {:error, reason} ->
        {:error, "Commit step failed: #{reason}"}
    end
  end

  defp maybe_commit_and_push(_claude_result, _task, _worktree_path, _branch_name), do: :ok

  defp run_claude(task, worktree_path) do
    human_id = task["human_id"]

    run_claude_cli(build_prompt(task),
      working_dir: worktree_path,
      label: human_id,
      timeout: stall_timeout()
    )
  end

  defp run_claude_cli(prompt, opts) do
    working_dir = Keyword.fetch!(opts, :working_dir)
    label = Keyword.get(opts, :label, "claude")
    timeout = Keyword.get(opts, :timeout, stall_timeout())
    model = Keyword.get(opts, :model)

    Logger.info("Executing Claude Code CLI for #{label} (stall timeout: #{timeout}ms)")

    claude_path = System.find_executable("claude")

    unless claude_path do
      {:error, "Claude Code CLI not found in PATH"}
    else
      model_flag = if model, do: " --model #{model}", else: ""

      cmd =
        "#{claude_path} -p #{escape_shell(prompt)}#{model_flag} --output-format stream-json --verbose --dangerously-skip-permissions < /dev/null 2>&1"

      port = Port.open({:spawn, cmd}, [:binary, :exit_status, cd: working_dir])

      collect_port_output(port, label, [], timeout)
    end
  end

  defp collect_port_output(port, human_id, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        for line <- String.split(data, "\n", trim: true) do
          Logger.info("[claude:#{human_id}] #{line}")
        end

        collect_port_output(port, human_id, [data | acc], timeout)

      {^port, {:exit_status, code}} ->
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        {:ok, %{exit_code: code, output: output}}
    after
      timeout ->
        Logger.error("Claude Code process stalled for task #{human_id} (exceeded #{timeout}ms)")
        kill_port(port)
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()

        {:error,
         "Claude Code process stalled after #{div(timeout, 1_000)}s of inactivity. " <>
           "Partial output (#{byte_size(output)} bytes) captured before kill."}
    end
  end

  defp kill_port(port) do
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true)

    receive do
      {^port, {:exit_status, _code}} -> :ok
    after
      5_000 ->
        Port.close(port)
    end
  rescue
    _ -> Port.close(port)
  end

  defp stall_timeout do
    CitadelAgent.config(:stall_timeout_ms) || @default_stall_timeout
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

  defp capture_diff(worktree_path, base_branch, branch_name) do
    case System.cmd("git", ["diff", "#{base_branch}..#{branch_name}"],
           cd: worktree_path,
           stderr_to_stdout: true
         ) do
      {diff, 0} ->
        {:ok, diff}

      {output, _code} ->
        {:ok, output}
    end
  end

  @stripped_env_vars ~w(ANTHROPIC_API_KEY OPENAI_API_KEY CLAUDECODE)

  defp ensure_claude_auth(claude_path, working_dir, env, label) do
    {auth_output, auth_code} =
      System.cmd(claude_path, ["auth", "status"],
        cd: working_dir,
        stderr_to_stdout: true,
        env: env
      )

    Logger.info("[claude:#{label}] Auth status in worktree (exit #{auth_code}): #{String.trim(auth_output)}")

    has_sso? =
      auth_code == 0 and not String.contains?(auth_output, "\"email\":null") and
        not String.contains?(auth_output, "ANTHROPIC_API_KEY")

    unless has_sso? do
      Logger.warning("[claude:#{label}] SSO not active in worktree — CLI may fall back to API key auth")
    end
  end

  defp clean_env do
    System.get_env()
    |> Map.drop(@stripped_env_vars)
    |> Map.to_list()
  end

  defp escape_shell(str) do
    "'" <> String.replace(str, "'", "'\\''") <> "'"
  end

  defp determine_status(%{exit_code: 0}), do: "completed"
  defp determine_status(_), do: "failed"
end
