defmodule CitadelAgent.Runner do
  @moduledoc """
  Orchestrates task execution: creates an isolated git worktree, invokes Claude Code CLI,
  captures output and git diff, returns structured results. Cleans up the worktree on completion.

  Enforces a wallclock cap on each Claude Code invocation: runs that exceed the configured
  max duration (sourced from the server on agent connect) are killed and marked as failed.
  Helper invocations (commit message, PR body) keep a shorter inactivity-based stall timer.
  """

  require Logger

  @commit_stall_timeout 120_000
  @drain_after_result_ms 10_000

  def execute(task, project_path, opts \\ []) do
    human_id = task["human_id"]
    run_id = Keyword.get(opts, :run_id)
    feedback = Keyword.get(opts, :feedback)
    resume_session_id = Keyword.get(opts, :resume_session_id)
    branch_name = "citadel/task-#{human_id}"
    worktree_path = Path.join(project_path, ".worktrees/task-#{human_id}")
    base_branch = base_branch_for(task)

    with :ok <- fetch_origin(project_path),
         :ok <- maybe_ensure_feature_branch(task, project_path),
         :ok <- create_worktree(worktree_path, branch_name, base_branch, project_path) do
      starting_sha = capture_head_sha(worktree_path)

      result =
        try do
          with {:ok, claude_result} <-
                 run_claude(task, worktree_path,
                   run_id: run_id,
                   feedback: feedback,
                   resume_session_id: resume_session_id
                 ),
               :ok <- maybe_commit_and_push(claude_result, task, worktree_path, branch_name),
               {:ok, commits} <- capture_commits(worktree_path, starting_sha) do
            session_id = extract_session_id_from_stream_json(claude_result.output)

            {:ok,
             %{
               status: determine_status(claude_result),
               commits: commits,
               logs: claude_result.output,
               test_output: nil,
               error_message: nil,
               session_id: session_id
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

  defp maybe_merge_into_feature_branch(
         %{"parent_human_id" => parent_id} = task,
         task_branch,
         project_path
       )
       when is_binary(parent_id) do
    feature_branch = "citadel/feature/#{parent_id}"
    merge_into_feature_branch(task_branch, feature_branch, project_path)
    ensure_draft_pr(feature_branch, task, project_path)
  end

  defp maybe_merge_into_feature_branch(task, task_branch, project_path) do
    ensure_draft_pr(task_branch, task, project_path)
  end

  defp merge_into_feature_branch(task_branch, feature_branch, project_path) do
    merge_id = System.unique_integer([:positive])
    merge_worktree = Path.join(project_path, ".worktrees/merge-#{merge_id}")

    try do
      case create_merge_worktree(merge_worktree, feature_branch, project_path) do
        {:ok, :checked_out} ->
          do_merge_and_push(task_branch, feature_branch, merge_worktree, [
            "push",
            "origin",
            feature_branch
          ])

        {:ok, :detached} ->
          do_merge_and_push(task_branch, feature_branch, merge_worktree, [
            "push",
            "origin",
            "HEAD:refs/heads/#{feature_branch}"
          ])

        :error ->
          :ok
      end
    after
      remove_worktree(merge_worktree, project_path)
    end
  end

  defp create_merge_worktree(merge_worktree, feature_branch, project_path) do
    case System.cmd("git", ["worktree", "add", merge_worktree, feature_branch],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        {:ok, :checked_out}

      {_output, _code} ->
        case System.cmd("git", ["worktree", "add", "--detach", merge_worktree, feature_branch],
               cd: project_path,
               stderr_to_stdout: true
             ) do
          {_output, 0} ->
            Logger.info(
              "Created detached merge worktree (#{feature_branch} is checked out elsewhere)"
            )

            {:ok, :detached}

          {output, _code} ->
            Logger.warning("Failed to create merge worktree for #{feature_branch}: #{output}")
            :error
        end
    end
  end

  defp do_merge_and_push(task_branch, feature_branch, merge_worktree, push_args) do
    case System.cmd("git", ["merge", task_branch, "--no-edit"],
           cd: merge_worktree,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        case System.cmd("git", push_args,
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

    result =
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

    result
  end

  defp ensure_draft_pr(feature_branch, task, project_path) do
    pr_title_id = task["parent_human_id"] || task["human_id"]
    task_id = task["parent_task_id"] || task["id"]

    try do
      {:ok, {owner, repo}} = CitadelAgent.GitHub.parse_remote_url(project_path)

      pr_url =
        case CitadelAgent.GitHub.find_pull_request(owner, repo, feature_branch, "main") do
          {:ok, url} when is_binary(url) ->
            Logger.info("PR already exists for #{feature_branch}: #{url}")
            url

          _ ->
            {_, 0} =
              System.cmd("git", ["push", "-u", "origin", feature_branch],
                cd: project_path,
                stderr_to_stdout: true
              )

            Logger.info("Pushed #{feature_branch} to origin")

            pr_title = generate_pr_title(task, project_path, pr_title_id)
            {:ok, pr_body} = generate_pr_description(task, project_path)

            case CitadelAgent.GitHub.create_pull_request(
                   owner,
                   repo,
                   feature_branch,
                   "main",
                   pr_title,
                   pr_body
                 ) do
              {:ok, :already_exists} ->
                Logger.info("PR already exists for #{feature_branch} (detected during creation)")
                nil

              {:ok, url} ->
                Logger.info("Created draft PR: #{url}")
                url

              {:error, reason} ->
                Logger.warning("Failed to create PR for #{feature_branch}: #{reason}")
                nil
            end
        end

      if pr_url do
        set_forge_pr(task_id, pr_url)
      end
    rescue
      e ->
        Logger.warning("Failed to create PR for #{feature_branch}: #{Exception.message(e)}")
        Logger.warning("Stacktrace: #{Exception.format(:error, e, __STACKTRACE__)}")
    end
  end

  defp set_forge_pr(nil, _pr_url), do: :ok

  defp set_forge_pr(parent_task_id, pr_url) do
    case CitadelAgent.Client.update_task(parent_task_id, %{"forge_pr" => pr_url}) do
      {:ok, _task} ->
        Logger.info("Set forge_pr on parent task #{parent_task_id}: #{pr_url}")

      {:error, reason} ->
        Logger.warning(
          "Failed to set forge_pr on parent task #{parent_task_id}: #{inspect(reason)}"
        )
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
        Logger.info(
          "Created worktree at #{worktree_path} on branch #{branch_name} from #{base_branch}"
        )

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
           model: "sonnet",
           tools: ["Bash"],
           no_mcp: true
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

  def generate_pr_title(task, project_path, pr_title_id) do
    title = task["title"] || ""
    description = task["description"] || ""

    prompt = """
    Generate a short, descriptive pull request title (under 60 characters) for the following task. \
    Output ONLY the title text, nothing else. Do not use any tools or make any code changes. \
    Do not include the task ID — just the descriptive title.

    Task: #{title}

    #{description}
    """

    case run_claude_cli(String.trim(prompt),
           working_dir: project_path,
           label: "pr-title:#{task["human_id"]}",
           timeout: @commit_stall_timeout,
           model: "sonnet",
           tools: [],
           no_mcp: true
         ) do
      {:ok, %{exit_code: 0, output: output}} ->
        case extract_text_from_stream_json(output) do
          nil -> pr_title_id
          text -> "#{pr_title_id}: #{String.trim(text)}"
        end

      {:ok, %{exit_code: _code}} ->
        Logger.warning("PR title generation failed, using fallback")
        pr_title_id

      {:error, reason} ->
        Logger.warning("PR title generation failed: #{inspect(reason)}, using fallback")
        pr_title_id
    end
  end

  def generate_pr_description(task, project_path) do
    title = task["title"] || ""
    description = task["description"] || ""

    prompt = """
    Generate a concise GitHub pull request description in markdown for the following task. \
    Output ONLY the description text, nothing else. Do not use any tools or make any code changes.

    Task: #{title}

    #{description}
    """

    case run_claude_cli(String.trim(prompt),
           working_dir: project_path,
           label: "pr-desc:#{task["human_id"]}",
           timeout: @commit_stall_timeout,
           model: "sonnet",
           tools: [],
           no_mcp: true
         ) do
      {:ok, %{exit_code: 0, output: output}} ->
        case extract_text_from_stream_json(output) do
          nil -> {:ok, fallback_pr_description(title)}
          text -> {:ok, text}
        end

      {:ok, %{exit_code: _code}} ->
        Logger.warning("PR description generation failed, using fallback")
        {:ok, fallback_pr_description(title)}

      {:error, reason} ->
        Logger.warning("PR description generation failed: #{inspect(reason)}, using fallback")
        {:ok, fallback_pr_description(title)}
    end
  end

  @doc false
  def extract_session_id_from_stream_json(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce(nil, fn line, acc ->
      case Jason.decode(line) do
        {:ok, %{"type" => "result", "session_id" => session_id}} when is_binary(session_id) ->
          session_id

        _ ->
          acc
      end
    end)
  end

  @doc false
  def extract_text_from_stream_json(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce([], fn line, acc ->
      case Jason.decode(line) do
        {:ok, %{"type" => "assistant", "message" => %{"content" => content}}}
        when is_list(content) ->
          text =
            content
            |> Enum.filter(&(is_map(&1) and &1["type"] == "text"))
            |> Enum.map_join("", & &1["text"])

          [text | acc]

        {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
          [text | acc]

        {:ok, %{"type" => "result", "result" => result}} when is_map(result) ->
          text =
            (result["content"] || [])
            |> Enum.filter(&(is_map(&1) and &1["type"] == "text"))
            |> Enum.map_join("", & &1["text"])

          [text | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
    |> Enum.join("")
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp fallback_pr_description(title) do
    "Citadel task: #{title}"
  end

  defp run_claude(task, worktree_path, opts) do
    human_id = task["human_id"]
    run_id = Keyword.get(opts, :run_id)
    feedback = Keyword.get(opts, :feedback)
    resume_session_id = Keyword.get(opts, :resume_session_id)

    run_claude_cli(build_prompt(task, feedback, run_id),
      working_dir: worktree_path,
      label: human_id,
      max_run_ms: CitadelAgent.Socket.max_run_ms(),
      run_id: run_id,
      resume_session_id: resume_session_id
    )
  end

  defp run_claude_cli(prompt, opts) do
    working_dir = Keyword.fetch!(opts, :working_dir)
    label = Keyword.get(opts, :label, "claude")
    inactivity_timeout = Keyword.get(opts, :timeout)
    max_run_ms = Keyword.get(opts, :max_run_ms)
    model = Keyword.get(opts, :model)
    run_id = Keyword.get(opts, :run_id)
    resume_session_id = Keyword.get(opts, :resume_session_id)
    tools = Keyword.get(opts, :tools)
    no_mcp = Keyword.get(opts, :no_mcp, false)

    mode =
      cond do
        is_integer(inactivity_timeout) -> {:inactivity, inactivity_timeout}
        is_integer(max_run_ms) -> {:wallclock, max_run_ms}
        true -> {:wallclock, CitadelAgent.Socket.max_run_ms()}
      end

    Logger.info("Executing Claude Code CLI for #{label} (#{describe_mode(mode)})")

    claude_path = System.find_executable("claude")

    if is_nil(claude_path) do
      {:error, "Claude Code CLI not found in PATH"}
    else
      claude_args =
        build_claude_args(prompt,
          resume_session_id: resume_session_id,
          model: model,
          tools: tools,
          no_mcp: no_mcp
        )

      exec_opts = [
        :stdout,
        {:stderr, :stdout},
        :monitor,
        {:group, 0},
        :kill_group,
        {:cd, working_dir}
      ]

      case :exec.run([claude_path | claude_args], exec_opts) do
        {:ok, pid, os_pid} ->
          collect_output(pid, os_pid, label, [], "", mode_with_deadline(mode), run_id)

        {:error, reason} ->
          {:error, "Failed to launch Claude Code CLI: #{inspect(reason)}"}
      end
    end
  end

  defp build_claude_args(prompt, opts) do
    resume_session_id = Keyword.get(opts, :resume_session_id)
    model = Keyword.get(opts, :model)
    tools = Keyword.get(opts, :tools)
    no_mcp = Keyword.get(opts, :no_mcp, false)

    base = [
      "-p",
      prompt,
      "--output-format",
      "stream-json",
      "--verbose",
      "--dangerously-skip-permissions"
    ]

    base = if resume_session_id, do: base ++ ["--resume", resume_session_id], else: base
    base = if model, do: base ++ ["--model", model], else: base

    base =
      case tools do
        nil -> base
        [] -> base ++ ["--tools", ""]
        list -> base ++ ["--tools", Enum.join(list, ",")]
      end

    if no_mcp, do: base ++ ["--strict-mcp-config"], else: base
  end

  defp describe_mode({:inactivity, ms}), do: "stall timeout: #{ms}ms"
  defp describe_mode({:wallclock, ms}), do: "max run: #{div(ms, 1_000)}s"

  defp mode_with_deadline({:wallclock, ms}),
    do: {:wallclock, ms, System.monotonic_time(:millisecond) + ms}

  defp mode_with_deadline({:inactivity, ms}), do: {:inactivity, ms}

  defp collect_output(pid, os_pid, human_id, acc, buffer, mode, run_id) do
    timeout = receive_timeout(mode)

    receive do
      {stream, ^os_pid, data} when stream in [:stdout, :stderr] ->
        {lines, buffer} = split_lines(buffer, data)
        log_and_stream(lines, human_id, run_id)

        new_mode = maybe_start_drain(mode, lines, human_id)
        collect_output(pid, os_pid, human_id, [data | acc], buffer, new_mode, run_id)

      {:DOWN, ^os_pid, :process, ^pid, reason} ->
        {acc, buffer} = drain_pending_output(os_pid, acc, buffer, human_id, run_id)
        flush_buffer(buffer, human_id, run_id)
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        {:ok, %{exit_code: exit_code_from_reason(reason), output: output}}
    after
      timeout ->
        stop_and_flush(pid, os_pid)
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        handle_timeout(mode, human_id, output)
    end
  end

  # erlexec delivers binary chunks without guaranteed line boundaries, so we
  # carry the trailing partial line forward in `buffer` until its newline arrives.
  defp split_lines(buffer, data) do
    parts = String.split(buffer <> data, "\n")
    {lines, [rest]} = Enum.split(parts, -1)
    {Enum.reject(lines, &(&1 == "")), rest}
  end

  defp log_and_stream(lines, human_id, run_id) do
    for line <- lines, do: Logger.info("[claude:#{human_id}] #{line}")
    push_lines_to_stream(run_id, lines)
  end

  defp flush_buffer("", _human_id, _run_id), do: :ok
  defp flush_buffer(buffer, human_id, run_id), do: log_and_stream([buffer], human_id, run_id)

  # Sweep any stdout that raced ahead of the DOWN message into the final output.
  defp drain_pending_output(os_pid, acc, buffer, human_id, run_id) do
    receive do
      {stream, ^os_pid, data} when stream in [:stdout, :stderr] ->
        {lines, buffer} = split_lines(buffer, data)
        log_and_stream(lines, human_id, run_id)
        drain_pending_output(os_pid, [data | acc], buffer, human_id, run_id)
    after
      0 -> {acc, buffer}
    end
  end

  defp exit_code_from_reason(:normal), do: 0

  defp exit_code_from_reason({:exit_status, status}) do
    case :exec.status(status) do
      {:status, code} -> code
      {:signal, _signal, _core} -> 1
    end
  end

  defp exit_code_from_reason(_reason), do: 1

  defp maybe_start_drain({:drain, _deadline, _prior} = mode, _lines, _human_id), do: mode

  defp maybe_start_drain(mode, lines, human_id) do
    if Enum.any?(lines, &result_event_line?/1) do
      deadline = System.monotonic_time(:millisecond) + @drain_after_result_ms

      Logger.info(
        "[claude:#{human_id}] result event received; draining for #{@drain_after_result_ms}ms before force-kill"
      )

      {:drain, deadline, mode}
    else
      mode
    end
  end

  defp result_event_line?(line) do
    case Jason.decode(String.trim(line)) do
      {:ok, %{"type" => "result"}} -> true
      _ -> false
    end
  end

  defp receive_timeout({:inactivity, ms}), do: ms

  defp receive_timeout({:wallclock, _total, deadline}),
    do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp receive_timeout({:drain, deadline, _prior}),
    do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp handle_timeout({:drain, _deadline, _prior}, human_id, output) do
    Logger.warning(
      "[claude:#{human_id}] result event emitted but process did not exit within drain window; force-killed process group and treating as success"
    )

    {:ok, %{exit_code: 0, output: output}}
  end

  defp handle_timeout({:inactivity, ms}, human_id, output) do
    Logger.error("Claude Code process stalled for task #{human_id} (exceeded #{ms}ms)")

    {:error,
     "Claude Code process stalled after #{div(ms, 1_000)}s of inactivity. " <>
       "Partial output (#{byte_size(output)} bytes) captured before kill."}
  end

  defp handle_timeout({:wallclock, total_ms, _deadline}, human_id, output) do
    Logger.error("Claude Code run for task #{human_id} exceeded wallclock cap (#{total_ms}ms)")

    {:error,
     "Claude Code run exceeded the configured #{div(total_ms, 1_000)}s max duration. " <>
       "Partial output (#{byte_size(output)} bytes) captured before kill."}
  end

  defp push_lines_to_stream(nil, _lines), do: :ok

  defp push_lines_to_stream(run_id, lines) do
    for line <- lines do
      trimmed = String.trim(line)

      if trimmed != "" do
        try do
          CitadelAgent.Socket.push_stream_event(run_id, trimmed)
        rescue
          e -> Logger.debug("Failed to push stream event: #{Exception.message(e)}")
        end
      end
    end

    :ok
  end

  # :exec.stop sends SIGTERM then SIGKILL to the whole process group (kill_group),
  # taking down Claude and every subprocess it spawned. Drain any straggling
  # output and the DOWN message so they don't pollute the long-lived Worker mailbox.
  defp stop_and_flush(pid, os_pid) do
    :exec.stop(pid)
    flush_until_down(pid, os_pid)
  end

  defp flush_until_down(pid, os_pid) do
    receive do
      {stream, ^os_pid, _data} when stream in [:stdout, :stderr] ->
        flush_until_down(pid, os_pid)

      {:DOWN, ^os_pid, :process, ^pid, _reason} ->
        :ok
    after
      5_000 -> :ok
    end
  end

  defp build_prompt(task, feedback \\ nil, run_id \\ nil) do
    title = task["title"] || ""
    description = task["description"] || ""

    base =
      """
      Task: #{title}

      #{description}
      """
      |> String.trim()

    base =
      case feedback do
        nil ->
          base

        body ->
          base <>
            "\n\n## Feedback - Changes Requested\n" <>
            "The following feedback was provided on your previous work. Address these changes:\n\n" <>
            body
      end

    base =
      if run_id do
        base <> "\n\n## Agent Run ID\n#{run_id}"
      else
        base
      end

    base <>
      "\n\n## Asking for User Input\n" <>
      "If you reach a point where you cannot continue without clarification from the user, use\n" <>
      "the ask_question MCP tool with your agent_run_id and the task_id. Provide all your\n" <>
      "questions clearly in the body. After calling ask_question, you MUST exit immediately\n" <>
      "without making any further tool calls or code changes."
  end

  defp capture_head_sha(worktree_path) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: worktree_path, stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  end

  defp capture_commits(worktree_path, starting_sha) when is_binary(starting_sha) do
    case System.cmd("git", ["log", "--format=%H%n%s", "#{starting_sha}..HEAD"],
           cd: worktree_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        commits =
          output
          |> String.trim()
          |> String.split("\n")
          |> Enum.chunk_every(2)
          |> Enum.filter(fn chunk -> length(chunk) == 2 end)
          |> Enum.map(fn [sha, message] -> %{"sha" => sha, "message" => message} end)

        {:ok, commits}

      {_output, _code} ->
        {:ok, []}
    end
  end

  defp capture_commits(_worktree_path, _starting_sha), do: {:ok, []}

  defp determine_status(%{exit_code: 0}), do: "completed"
  defp determine_status(_), do: "failed"
end
