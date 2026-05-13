# Dev-only seed for the task-details activity timeline redesign.
#
# Idempotent — re-running drops + recreates the seed task so the activity
# timeline is the same shape every time (useful for visual checks).
#
# Run with:
#   mix run priv/repo/dev_seed_task_activity.exs
#
# Sign in afterwards with:
#   email: dev@citadel.test
#   password: DevPassword123!

require Ash.Query

alias Citadel.Accounts
alias Citadel.Tasks

dev_email = "dev@citadel.test"
dev_password = "DevPassword123!"
task_title = "Github Actions CI"

# --- Task states (matches priv/repo/seeds.exs so this is safe in any env) ----

Tasks.create_task_state!(%{name: "Todo", order: 1}, upsert?: true, upsert_identity: :unique_name)

Tasks.create_task_state!(%{name: "In Progress", order: 2},
  upsert?: true,
  upsert_identity: :unique_name
)

Tasks.create_task_state!(%{name: "Complete", order: 3},
  upsert?: true,
  upsert_identity: :unique_name
)

in_progress_state =
  Tasks.list_task_states!(authorize?: false)
  |> Enum.find(&(&1.name == "In Progress"))

# --- Dev user (find by email or register; register_with_password also creates
#      the user's Personal organization + Personal workspace via after_action). -

user =
  case Accounts.User
       |> Ash.Query.for_read(:get_by_email, %{email: dev_email}, authorize?: false)
       |> Ash.read_one(authorize?: false) do
    {:ok, %Accounts.User{} = u} ->
      u

    _ ->
      strategy = AshAuthentication.Info.strategy!(Accounts.User, :password)

      {:ok, u} =
        AshAuthentication.Strategy.action(strategy, :register, %{
          "email" => dev_email,
          "password" => dev_password,
          "password_confirmation" => dev_password
        })

      u
  end

[workspace | _] = Accounts.list_workspaces!(actor: user, load: [:owner])
tenant = workspace.id

# --- Reset any previous seed task so re-runs are deterministic. ---

Tasks.list_tasks!(actor: user, tenant: tenant)
|> Enum.filter(&(&1.title == task_title))
|> Enum.each(&Tasks.destroy_task!(&1, actor: user, tenant: tenant))

# --- Seed task. ---

task =
  Tasks.create_task!(
    %{
      title: task_title,
      description: """
      We need a proper CI pipeline for this project. At minimum we should run
      formatting, linting, security, and test checks. Before you begin, do
      some research on best practices for CI pipelines for elixir
      applications. Try to parallelize and cache whenever possible to keep
      execution times to a minimum.
      """,
      task_state_id: in_progress_state.id,
      priority: :high,
      agent_eligible: true
    },
    actor: user,
    tenant: tenant
  )

# MaybeEnqueueAgentWork autocreates a :new_task work item on task create when
# agent_eligible is true. The agent_work_items table has a unique partial
# index ("one active per task") that would later collide with the
# request-changes work item the seed creates further down. Cancel any
# autocreated work items so the rest of the seed is free to run.
Citadel.Tasks.AgentWorkItem
|> Ash.Query.filter(task_id == ^task.id and status in [:pending, :claimed])
|> Ash.read!(authorize?: false, tenant: tenant)
|> Enum.each(&Tasks.cancel_agent_work_item!(&1, authorize?: false, tenant: tenant))

opts = [actor: user, tenant: tenant]

# Helper: create a run, then update it to its final shape.
update_run = fn run, attrs ->
  {:ok, updated} = Tasks.update_agent_run(run, attrs, actor: user, tenant: tenant)
  updated
end

# 1) Two stalled / failed retries in a row.
run1 = Tasks.create_agent_run!(%{task_id: task.id, status: :pending}, opts)

_ =
  update_run.(run1, %{
    status: :failed,
    started_at: DateTime.utc_now() |> DateTime.add(-96 * 3600, :second),
    completed_at: DateTime.utc_now() |> DateTime.add(-95 * 3600, :second),
    error_message:
      "Claude Code process stalled after 600s of inactivity. Partial output (425,140 bytes) captured before kill.",
    test_output: "mix format --check-formatted\n** stalled — no stdout for 600s, killed."
  })

run2 = Tasks.create_agent_run!(%{task_id: task.id, status: :pending}, opts)

_ =
  update_run.(run2, %{
    status: :failed,
    started_at: DateTime.utc_now() |> DateTime.add(-94 * 3600, :second),
    completed_at: DateTime.utc_now() |> DateTime.add(-93 * 3600, :second),
    error_message:
      "Claude Code process stalled after 600s of inactivity. Partial output (141,260 bytes) captured before kill.",
    test_output: "  warning: unused variable `pipeline_opts`\n** stalled — no stdout for 600s, killed."
  })

# 2) A cancelled run (reaped).
run3 = Tasks.create_agent_run!(%{task_id: task.id, status: :pending}, opts)

_ =
  update_run.(run3, %{
    status: :cancelled,
    started_at: DateTime.utc_now() |> DateTime.add(-36 * 3600, :second),
    completed_at: DateTime.utc_now() |> DateTime.add(-35 * 3600, :second),
    error_message: "Reaped: running run had no connected agent."
  })

# 3) A completed run with commits + test output.
run4 = Tasks.create_agent_run!(%{task_id: task.id, status: :pending}, opts)

_ =
  update_run.(run4, %{
    status: :completed,
    started_at: DateTime.utc_now() |> DateTime.add(-12 * 3600, :second),
    completed_at:
      DateTime.utc_now() |> DateTime.add(-11 * 3600 - 42 * 60, :second),
    session_id: "sess_8a4f21c9b002dabcdef0",
    commits: [
      %{"sha" => "8a4f21cabcdef", "message" => "feat(ci): parallel test matrix with cached deps"},
      %{"sha" => "c9b002dabcdef", "message" => "feat(ci): add credo + sobelow security checks"}
    ],
    test_output: """
    Compiling 87 files (.ex)
    Generated citadel app

    Finished in 7.4 seconds (5.2s async, 2.2s sync)
    412 tests, 0 failures
    """
  })

# 4) A user comment that requests changes (queues a new agent run).
_change_request =
  Tasks.create_request_changes_comment!(
    %{
      body: """
      Address the **credo issues** that are causing the pipeline to fail so this can be merged.

      Specifically the warnings flagged in:

      - `lib/citadel/billing/invoice.ex` — unused alias
      - `lib/citadel/jobs/reaper.ex` — function complexity > 10
      - `lib/citadel_web/router.ex` — pipe chain depth

      Once those are clean, re-run `mix credo --strict` and confirm exit `0` before pushing.
      """,
      task_id: task.id
    },
    actor: user,
    tenant: tenant
  )

# 5) A plain follow-up comment (no markdown — exercises the simpler row).
_comment =
  Tasks.create_comment!(
    %{body: "Thanks — I'll spin up another run once those are clean.", task_id: task.id},
    actor: user,
    tenant: tenant
  )

# 6) An in-progress run currently running (pulse on the rail).
running_run = Tasks.create_agent_run!(%{task_id: task.id, status: :pending}, opts)

running_run =
  update_run.(running_run, %{
    status: :running,
    started_at: DateTime.utc_now() |> DateTime.add(-90, :second),
    session_id: "sess_resolving_credo_warnings_42a"
  })

IO.puts("""

Seed complete.

  user:     #{dev_email}
  password: #{dev_password}
  workspace: #{workspace.name} (#{workspace.id})
  task:     #{task.human_id} — #{task.title}
  url:      http://localhost:4100/tasks/#{task.human_id}

  Activities created:
    - 2 failed retries (#{run1.id}, #{run2.id})
    - 1 cancelled (#{run3.id})
    - 1 completed with commits (#{run4.id})
    - 1 change-request comment + 1 plain comment
    - 1 in-progress run (#{running_run.id})
""")
