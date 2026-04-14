defmodule Citadel.Tasks.ClaimNextTaskTest do
  use Citadel.DataCase, async: false

  alias Citadel.Tasks

  setup do
    user = generate(user())
    workspace = generate(workspace([], actor: user))

    todo_state =
      Tasks.create_task_state!(%{
        name: "To Do #{System.unique_integer([:positive])}",
        order: 1,
        is_complete: false
      })

    done_state =
      Tasks.create_task_state!(%{
        name: "Done #{System.unique_integer([:positive])}",
        order: 3,
        is_complete: true
      })

    require Ash.Query

    in_review_state =
      case Citadel.Tasks.TaskState
           |> Ash.Query.filter(name == "In Review")
           |> Ash.read_one(authorize?: false) do
        {:ok, nil} ->
          Tasks.create_task_state!(%{name: "In Review", order: 2, is_complete: false})

        {:ok, existing} ->
          existing
      end

    in_progress_state =
      case Citadel.Tasks.TaskState
           |> Ash.Query.filter(name == "In Progress")
           |> Ash.read_one(authorize?: false) do
        {:ok, nil} ->
          Tasks.create_task_state!(%{name: "In Progress", order: 2, is_complete: false})

        {:ok, existing} ->
          existing
      end

    {:ok,
     user: user,
     workspace: workspace,
     todo_state: todo_state,
     done_state: done_state,
     in_review_state: in_review_state,
     in_progress_state: in_progress_state}
  end

  defp create_eligible_task(ctx, opts \\ []) do
    Tasks.create_task!(
      %{
        title: "Eligible Task #{System.unique_integer([:positive])}",
        task_state_id: ctx.todo_state.id,
        agent_eligible: true,
        priority: Keyword.get(opts, :priority, :medium)
      },
      actor: ctx.user,
      tenant: ctx.workspace.id
    )
  end

  describe "claim_next_task/1" do
    test "claims the next eligible task and returns a running agent run", ctx do
      task = create_eligible_task(ctx)

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id,
          load: [task: [:task_state, :parent_task]]
        )

      assert agent_run.status == :running
      assert agent_run.started_at != nil
      assert agent_run.task_id == task.id
      assert agent_run.workspace_id == ctx.workspace.id
      assert agent_run.user_id == ctx.user.id
      assert agent_run.task.id == task.id
      assert agent_run.task.task_state.id == ctx.in_progress_state.id
    end

    test "returns error when no eligible tasks exist", ctx do
      assert {:error, _} =
               Tasks.claim_next_task(
                 actor: ctx.user,
                 tenant: ctx.workspace.id
               )
    end

    test "skips tasks with active (pending) agent runs", ctx do
      task_with_run = create_eligible_task(ctx)
      eligible_task = create_eligible_task(ctx)

      Tasks.create_agent_run!(
        %{task_id: task_with_run.id, status: :pending},
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert agent_run.task_id == eligible_task.id
    end

    test "skips tasks with running agent runs", ctx do
      task_with_run = create_eligible_task(ctx)
      eligible_task = create_eligible_task(ctx)

      run =
        Tasks.create_agent_run!(
          %{task_id: task_with_run.id},
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      Tasks.update_agent_run!(
        run,
        %{status: :running, started_at: DateTime.utc_now()},
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert agent_run.task_id == eligible_task.id
    end

    test "allows tasks with completed/failed/cancelled agent runs", ctx do
      task = create_eligible_task(ctx)

      run =
        Tasks.create_agent_run!(
          %{task_id: task.id},
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      Tasks.update_agent_run!(
        run,
        %{status: :completed, completed_at: DateTime.utc_now()},
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert agent_run.task_id == task.id
    end

    test "skips completed tasks", ctx do
      Tasks.create_task!(
        %{
          title: "Completed Task #{System.unique_integer([:positive])}",
          task_state_id: ctx.done_state.id,
          agent_eligible: true
        },
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      eligible_task = create_eligible_task(ctx)

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert agent_run.task_id == eligible_task.id
    end

    test "skips tasks in 'In Review' state", ctx do
      Tasks.create_task!(
        %{
          title: "In Review Task #{System.unique_integer([:positive])}",
          task_state_id: ctx.in_review_state.id,
          agent_eligible: true
        },
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      eligible_task = create_eligible_task(ctx)

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert agent_run.task_id == eligible_task.id
    end

    test "skips tasks with incomplete dependencies", ctx do
      dependency_task =
        Tasks.create_task!(
          %{
            title: "Dependency #{System.unique_integer([:positive])}",
            task_state_id: ctx.todo_state.id
          },
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      blocked_task = create_eligible_task(ctx)

      Tasks.create_task_dependency!(
        %{task_id: blocked_task.id, depends_on_task_id: dependency_task.id},
        authorize?: false
      )

      unblocked_task = create_eligible_task(ctx)

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert agent_run.task_id == unblocked_task.id
    end

    test "allows tasks with completed dependencies", ctx do
      dependency_task =
        Tasks.create_task!(
          %{
            title: "Completed Dep #{System.unique_integer([:positive])}",
            task_state_id: ctx.done_state.id
          },
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      task = create_eligible_task(ctx)

      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: dependency_task.id},
        authorize?: false
      )

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert agent_run.task_id == task.id
    end

    test "skips tasks where agent_eligible is false", ctx do
      Tasks.create_task!(
        %{
          title: "Not Eligible #{System.unique_integer([:positive])}",
          task_state_id: ctx.todo_state.id,
          agent_eligible: false
        },
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      eligible_task = create_eligible_task(ctx)

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert agent_run.task_id == eligible_task.id
    end

    test "prioritizes higher priority tasks", ctx do
      _low = create_eligible_task(ctx, priority: :low)
      urgent = create_eligible_task(ctx, priority: :urgent)
      _medium = create_eligible_task(ctx, priority: :medium)

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert agent_run.task_id == urgent.id
    end

    test "uses inserted_at as tiebreaker for same priority", ctx do
      first = create_eligible_task(ctx, priority: :high)
      _second = create_eligible_task(ctx, priority: :high)

      agent_run =
        Tasks.claim_next_task!(
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert agent_run.task_id == first.id
    end
  end
end
