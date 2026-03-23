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

  defp maybe_merge_into_feature_branch(%{"parent_human_id" => parent_id} = task, task_branch, project_path)
       when is_binary(parent_id) do
    feature_branch = "citadel/feature/#{parent_id}"
    merge_into_feature_branch(task_branch, feature_branch, project_path)
    ensure_draft_pr(feature_branch, task, project_path)
  end

  defp maybe_merge_into_feature_branch(_task, _task_branch, _project_path), do: :ok

  defp merge_into_feature_branch(task_branch, feature_branch, project_path) do
    merge_id = System.unique_integer([:positive])
    merge_worktree = Path.join(project_path, ".worktrees/merge-#{merge_id}")

    try do
      case create_merge_worktree(merge_worktree, feature_branch, project_path) do
        {:ok, :checked_out} ->
          do_merge_and_push(task_branch, feature_branch, merge_worktree, ["push", "origin", feature_branch])

        {:ok, :detached} ->
          do_merge_and_push(task_branch, feature_branch, merge_worktree, ["push", "origin", "HEAD:refs/heads/#{feature_branch}"])

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
            Logger.info("Created detached merge worktree (#{feature_branch} is checked out elsewhere)")
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

  defp maybe_ensure_feature_branch(%{"parent_human_id" => parent_id} = task, project_path)
       when is_binary(parent_id) do
    ensure_feature_branch("citadel/feature/#{parent_id}", task, project_path)
  end

  defp maybe_ensure_feature_branch(_task, _project_path), do: :ok

  defp ensure_feature_branch(feature_branch, task, project_path) do
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
    parent_id = task["parent_human_id"]

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

            {:ok, pr_body} = generate_pr_description(task, project_path)

            case CitadelAgent.GitHub.create_pull_request(owner, repo, feature_branch, "main", parent_id, pr_body) do
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
        set_forge_pr(task["parent_task_id"], pr_url)
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
        Logger.warning("Failed to set forge_pr on parent task #{parent_task_id}: #{inspect(reason)}")
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
           model: "sonnet",
           allowed_tools: ["Bash"]
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
           model: "sonnet"
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
        {:ok, %{"type" => "assistant", "message" => %{"content" => content}}} when is_list(content) ->
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
      timeout: stall_timeout(),
      run_id: run_id,
      resume_session_id: resume_session_id
    )
  end

  defp run_claude_cli(prompt, opts) do
    working_dir = Keyword.fetch!(opts, :working_dir)
    label = Keyword.get(opts, :label, "claude")
    timeout = Keyword.get(opts, :timeout, stall_timeout())
    model = Keyword.get(opts, :model)
    run_id = Keyword.get(opts, :run_id)
    resume_session_id = Keyword.get(opts, :resume_session_id)
    allowed_tools = Keyword.get(opts, :allowed_tools)

    Logger.info("Executing Claude Code CLI for #{label} (stall timeout: #{timeout}ms)")

    claude_path = System.find_executable("claude")

    unless claude_path do
      {:error, "Claude Code CLI not found in PATH"}
    else
      model_flag = if model, do: " --model #{model}", else: ""
      resume_flag = if resume_session_id, do: " --resume #{escape_shell(resume_session_id)}", else: ""
      tools_flag = if allowed_tools, do: " --allowedTools #{Enum.join(allowed_tools, ",")}", else: ""

      cmd =
        "#{claude_path} -p #{escape_shell(prompt)}#{resume_flag}#{model_flag}#{tools_flag} --output-format stream-json --verbose --dangerously-skip-permissions < /dev/null 2>&1"

      port = Port.open({:spawn, cmd}, [:binary, :exit_status, cd: working_dir])

      collect_port_output(port, label, [], timeout, run_id)
    end
  end

  defp collect_port_output(port, human_id, acc, timeout, run_id) do
    receive do
      {^port, {:data, data}} ->
        lines = String.split(data, "\n", trim: true)

        for line <- lines do
          Logger.info("[claude:#{human_id}] #{line}")
        end

        push_lines_to_stream(run_id, lines)

        collect_port_output(port, human_id, [data | acc], timeout, run_id)

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
