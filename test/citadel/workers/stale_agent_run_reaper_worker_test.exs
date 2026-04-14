defmodule Citadel.Workers.StaleAgentRunReaperWorkerTest do
  use Citadel.DataCase, async: false

  alias Citadel.Tasks
  alias Citadel.Workers.StaleAgentRunReaperWorker

  setup do
    user = generate(user())
    workspace = generate(workspace([], actor: user))

    task_state =
      Tasks.create_task_state!(%{
        name: "To Do #{System.unique_integer([:positive])}",
        order: 1,
        is_complete: false
      })

    task =
      Tasks.create_task!(
        %{
          title: "Test Task #{System.unique_integer([:positive])}",
          task_state_id: task_state.id,
          agent_eligible: true
        },
        actor: user,
        tenant: workspace.id
      )

    {:ok, user: user, workspace: workspace, task: task, task_state: task_state}
  end

  defp create_run(ctx, attrs \\ %{}) do
    Tasks.create_agent_run!(
      Map.merge(%{task_id: ctx.task.id}, attrs),
      actor: ctx.user,
      tenant: ctx.workspace.id
    )
  end

  defp set_run_status(run, status, ctx) do
    Tasks.update_agent_run!(
      run,
      %{status: status, started_at: DateTime.utc_now()},
      actor: ctx.user,
      tenant: ctx.workspace.id
    )
  end

  defp backdate_run(run, minutes) do
    past = DateTime.add(DateTime.utc_now(), -minutes, :minute)
    {:ok, uuid_binary} = Ecto.UUID.dump(run.id)

    Citadel.Repo.query!(
      "UPDATE agent_runs SET updated_at = $1 WHERE id = $2",
      [past, uuid_binary]
    )
  end

  defp reload_run(run, ctx) do
    Tasks.get_agent_run!(run.id,
      actor: ctx.user,
      tenant: ctx.workspace.id
    )
  end

  describe "perform/1" do
    test "reaps a stale running run", ctx do
      run = create_run(ctx)
      run = set_run_status(run, :running, ctx)
      backdate_run(run, 45)

      assert :ok = perform_job(StaleAgentRunReaperWorker, %{})

      reloaded = reload_run(run, ctx)
      assert reloaded.status == :failed
      assert reloaded.error_message =~ "Reaped"
      assert reloaded.completed_at != nil
    end

    test "reaps a stale pending run", ctx do
      run = create_run(ctx)
      backdate_run(run, 90)

      assert :ok = perform_job(StaleAgentRunReaperWorker, %{})

      reloaded = reload_run(run, ctx)
      assert reloaded.status == :failed
      assert reloaded.error_message =~ "Reaped"
    end

    test "does not reap a recently-updated running run", ctx do
      run = create_run(ctx)
      run = set_run_status(run, :running, ctx)

      assert :ok = perform_job(StaleAgentRunReaperWorker, %{})

      reloaded = reload_run(run, ctx)
      assert reloaded.status == :running
    end

    test "does not reap completed runs", ctx do
      run = create_run(ctx)

      run =
        Tasks.update_agent_run!(
          run,
          %{status: :completed, completed_at: DateTime.utc_now()},
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      backdate_run(run, 120)

      assert :ok = perform_job(StaleAgentRunReaperWorker, %{})

      reloaded = reload_run(run, ctx)
      assert reloaded.status == :completed
    end

    test "does not reap failed runs", ctx do
      run = create_run(ctx)

      run =
        Tasks.update_agent_run!(
          run,
          %{status: :failed, completed_at: DateTime.utc_now()},
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      backdate_run(run, 120)

      assert :ok = perform_job(StaleAgentRunReaperWorker, %{})

      reloaded = reload_run(run, ctx)
      assert reloaded.status == :failed
    end

    test "does not reap cancelled runs", ctx do
      run = create_run(ctx)
      run = set_run_status(run, :running, ctx)

      Tasks.cancel_agent_run!(run,
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      run = reload_run(run, ctx)
      backdate_run(run, 120)

      assert :ok = perform_job(StaleAgentRunReaperWorker, %{})

      reloaded = reload_run(run, ctx)
      assert reloaded.status == :cancelled
    end

    test "does not reap input_requested runs", ctx do
      run = create_run(ctx)
      run = set_run_status(run, :running, ctx)

      run =
        Tasks.request_agent_run_input!(run,
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      backdate_run(run, 120)

      assert :ok = perform_job(StaleAgentRunReaperWorker, %{})

      reloaded = reload_run(run, ctx)
      assert reloaded.status == :input_requested
    end

    test "syncs work item status when reaping a claimed run", ctx do
      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id,
          load: [:work_item]
        )

      work_item = agent_run.work_item
      assert work_item.status == :claimed

      backdate_run(agent_run, 45)

      assert :ok = perform_job(StaleAgentRunReaperWorker, %{})

      require Ash.Query

      reloaded_work_item =
        Citadel.Tasks.AgentWorkItem
        |> Ash.Query.filter(id == ^work_item.id)
        |> Ash.read_one!(authorize?: false, tenant: ctx.workspace.id)

      assert reloaded_work_item.status == :completed
    end

    test "handles multiple stale runs across workspaces", ctx do
      run1 = create_run(ctx)
      run1 = set_run_status(run1, :running, ctx)
      backdate_run(run1, 45)

      user2 = generate(user())
      workspace2 = generate(workspace([], actor: user2))

      task2 =
        Tasks.create_task!(
          %{
            title: "Task 2 #{System.unique_integer([:positive])}",
            task_state_id: ctx.task_state.id,
            agent_eligible: true
          },
          actor: user2,
          tenant: workspace2.id
        )

      run2 =
        Tasks.create_agent_run!(
          %{task_id: task2.id},
          actor: user2,
          tenant: workspace2.id
        )

      run2 = set_run_status(run2, :running, %{user: user2, workspace: workspace2})
      backdate_run(run2, 45)

      assert :ok = perform_job(StaleAgentRunReaperWorker, %{})

      reloaded1 = reload_run(run1, ctx)
      assert reloaded1.status == :failed

      reloaded2 = reload_run(run2, %{user: user2, workspace: workspace2})
      assert reloaded2.status == :failed
    end

    test "returns :ok when no stale runs exist", _ctx do
      assert :ok = perform_job(StaleAgentRunReaperWorker, %{})
    end
  end
end
