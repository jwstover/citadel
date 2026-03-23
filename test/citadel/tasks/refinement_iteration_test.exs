defmodule Citadel.Tasks.RefinementIterationTest do
  use Citadel.DataCase, async: true

  alias Citadel.Tasks

  setup do
    user = generate(user())
    workspace = generate(workspace([], actor: user))

    task_state =
      Tasks.create_task_state!(%{
        name: "Task State #{System.unique_integer([:positive])}",
        order: 1
      })

    task =
      Tasks.create_task!(
        %{
          title: "Test Task #{System.unique_integer([:positive])}",
          task_state_id: task_state.id,
          workspace_id: workspace.id
        },
        actor: user,
        tenant: workspace.id
      )

    agent_run =
      Tasks.create_agent_run!(
        %{task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

    cycle =
      Tasks.create_refinement_cycle!(
        %{agent_run_id: agent_run.id},
        actor: user,
        tenant: workspace.id
      )

    {:ok, user: user, workspace: workspace, agent_run: agent_run, cycle: cycle}
  end

  describe "create_refinement_iteration/2" do
    test "creates an iteration linked to a cycle", %{
      user: user,
      workspace: workspace,
      cycle: cycle
    } do
      now = DateTime.utc_now()

      iteration =
        Tasks.create_refinement_iteration!(
          %{
            refinement_cycle_id: cycle.id,
            iteration_number: 1,
            started_at: now
          },
          actor: user,
          tenant: workspace.id
        )

      assert iteration.refinement_cycle_id == cycle.id
      assert iteration.workspace_id == workspace.id
      assert iteration.iteration_number == 1
      assert iteration.status == :evaluated
    end

    test "creates an iteration with evaluation data", %{
      user: user,
      workspace: workspace,
      cycle: cycle
    } do
      eval_result = %{"checks" => [%{"name" => "tests_pass", "passed" => true}], "overall" => 0.9}

      iteration =
        Tasks.create_refinement_iteration!(
          %{
            refinement_cycle_id: cycle.id,
            iteration_number: 1,
            evaluation_result: eval_result,
            score: 0.9,
            feedback: "Tests pass but coverage is low",
            status: :evaluated,
            started_at: DateTime.utc_now()
          },
          actor: user,
          tenant: workspace.id
        )

      assert iteration.evaluation_result == eval_result
      assert iteration.score == 0.9
      assert iteration.feedback == "Tests pass but coverage is low"
    end

    test "non-member cannot create an iteration", %{workspace: workspace, cycle: cycle} do
      outsider = generate(user())

      assert_raise Ash.Error.Forbidden, fn ->
        Tasks.create_refinement_iteration!(
          %{refinement_cycle_id: cycle.id, iteration_number: 1},
          actor: outsider,
          tenant: workspace.id
        )
      end
    end

    test "broadcasts PubSub message on create", %{
      user: user,
      workspace: workspace,
      cycle: cycle
    } do
      CitadelWeb.Endpoint.subscribe("tasks:refinement:#{cycle.id}")

      Tasks.create_refinement_iteration!(
        %{refinement_cycle_id: cycle.id, iteration_number: 1},
        actor: user,
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:refinement:" <> _,
        event: "create"
      }
    end
  end

  describe "list_refinement_iterations/2" do
    test "returns iterations ordered by iteration_number", %{
      user: user,
      workspace: workspace,
      cycle: cycle
    } do
      for i <- [3, 1, 2] do
        Tasks.create_refinement_iteration!(
          %{refinement_cycle_id: cycle.id, iteration_number: i},
          actor: user,
          tenant: workspace.id
        )
      end

      iterations =
        Tasks.list_refinement_iterations!(cycle.id, actor: user, tenant: workspace.id)

      assert length(iterations) == 3
      assert Enum.map(iterations, & &1.iteration_number) == [1, 2, 3]
    end

    test "returns empty list when no iterations exist", %{
      user: user,
      workspace: workspace,
      cycle: cycle
    } do
      iterations =
        Tasks.list_refinement_iterations!(cycle.id, actor: user, tenant: workspace.id)

      assert iterations == []
    end
  end

  describe "update_refinement_iteration/2" do
    test "updates status and completed_at", %{
      user: user,
      workspace: workspace,
      cycle: cycle
    } do
      iteration =
        Tasks.create_refinement_iteration!(
          %{refinement_cycle_id: cycle.id, iteration_number: 1, started_at: DateTime.utc_now()},
          actor: user,
          tenant: workspace.id
        )

      now = DateTime.utc_now()

      updated =
        Tasks.update_refinement_iteration!(
          iteration,
          %{status: :accepted, completed_at: now},
          actor: user,
          tenant: workspace.id
        )

      assert updated.status == :accepted
      assert updated.completed_at != nil
    end
  end

  describe "cycle iterations relationship" do
    test "cycle can load its iterations", %{
      user: user,
      workspace: workspace,
      cycle: cycle
    } do
      for i <- 1..3 do
        Tasks.create_refinement_iteration!(
          %{refinement_cycle_id: cycle.id, iteration_number: i},
          actor: user,
          tenant: workspace.id
        )
      end

      loaded = Ash.load!(cycle, :iterations, tenant: workspace.id, authorize?: false)
      assert length(loaded.iterations) == 3
    end
  end

  describe "multitenancy" do
    test "iterations are scoped to workspace", %{
      user: user,
      workspace: workspace,
      cycle: cycle
    } do
      iteration =
        Tasks.create_refinement_iteration!(
          %{refinement_cycle_id: cycle.id, iteration_number: 1},
          actor: user,
          tenant: workspace.id
        )

      assert iteration.workspace_id == workspace.id
    end
  end
end
