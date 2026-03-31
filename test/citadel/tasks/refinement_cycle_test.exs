defmodule Citadel.Tasks.RefinementCycleTest do
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

    {:ok, user: user, workspace: workspace, task: task, agent_run: agent_run}
  end

  describe "create_refinement_cycle/2" do
    test "creates a cycle linked to an agent run", %{
      user: user,
      workspace: workspace,
      agent_run: agent_run
    } do
      cycle =
        Tasks.create_refinement_cycle!(
          %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      assert cycle.agent_run_id == agent_run.id
      assert cycle.workspace_id == workspace.id
      assert cycle.status == :running
      assert cycle.max_iterations == 3
      assert cycle.current_iteration == 0
      assert cycle.evaluator_config == %{}
      assert cycle.final_score == nil
    end

    test "accepts custom max_iterations and evaluator_config", %{
      user: user,
      workspace: workspace,
      agent_run: agent_run
    } do
      config = %{"type" => "code_quality", "threshold" => 0.8}

      cycle =
        Tasks.create_refinement_cycle!(
          %{agent_run_id: agent_run.id, max_iterations: 5, evaluator_config: config},
          actor: user,
          tenant: workspace.id
        )

      assert cycle.max_iterations == 5
      assert cycle.evaluator_config == config
    end

    test "non-member cannot create a cycle", %{workspace: workspace, agent_run: agent_run} do
      outsider = generate(user())

      assert_raise Ash.Error.Forbidden, fn ->
        Tasks.create_refinement_cycle!(
          %{agent_run_id: agent_run.id},
          actor: outsider,
          tenant: workspace.id
        )
      end
    end

    test "broadcasts PubSub message on create", %{
      user: user,
      workspace: workspace,
      agent_run: agent_run
    } do
      CitadelWeb.Endpoint.subscribe("tasks:refinement:#{agent_run.id}")

      Tasks.create_refinement_cycle!(
        %{agent_run_id: agent_run.id},
        actor: user,
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:refinement:" <> _,
        event: "create"
      }
    end
  end

  describe "complete_refinement_cycle/2" do
    test "marks cycle as passed with final score", %{
      user: user,
      workspace: workspace,
      agent_run: agent_run
    } do
      cycle =
        Tasks.create_refinement_cycle!(
          %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      completed =
        Tasks.complete_refinement_cycle!(
          cycle,
          %{final_score: 0.95},
          actor: user,
          tenant: workspace.id
        )

      assert completed.status == :passed
      assert completed.final_score == 0.95
    end
  end

  describe "fail_refinement_cycle/2" do
    test "marks cycle as failed_max_iterations by default", %{
      user: user,
      workspace: workspace,
      agent_run: agent_run
    } do
      cycle =
        Tasks.create_refinement_cycle!(
          %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      failed =
        Tasks.fail_refinement_cycle!(
          cycle,
          %{},
          actor: user,
          tenant: workspace.id
        )

      assert failed.status == :failed_max_iterations
    end

    test "marks cycle as error when specified", %{
      user: user,
      workspace: workspace,
      agent_run: agent_run
    } do
      cycle =
        Tasks.create_refinement_cycle!(
          %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      failed =
        Tasks.fail_refinement_cycle!(
          cycle,
          %{reason: :error},
          actor: user,
          tenant: workspace.id
        )

      assert failed.status == :error
    end
  end

  describe "update_refinement_cycle/2" do
    test "updates current_iteration", %{
      user: user,
      workspace: workspace,
      agent_run: agent_run
    } do
      cycle =
        Tasks.create_refinement_cycle!(
          %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      updated =
        Tasks.update_refinement_cycle!(
          cycle,
          %{current_iteration: 2},
          actor: user,
          tenant: workspace.id
        )

      assert updated.current_iteration == 2
    end
  end

  describe "agent_run relationship" do
    test "agent run can load its refinement cycle", %{
      user: user,
      workspace: workspace,
      agent_run: agent_run
    } do
      Tasks.create_refinement_cycle!(
        %{agent_run_id: agent_run.id},
        actor: user,
        tenant: workspace.id
      )

      loaded = Ash.load!(agent_run, :refinement_cycle, tenant: workspace.id, authorize?: false)
      assert loaded.refinement_cycle != nil
      assert loaded.refinement_cycle.agent_run_id == agent_run.id
    end
  end

  describe "multitenancy" do
    test "cycles are scoped to workspace", %{
      user: user,
      workspace: workspace,
      agent_run: agent_run
    } do
      cycle =
        Tasks.create_refinement_cycle!(
          %{agent_run_id: agent_run.id},
          actor: user,
          tenant: workspace.id
        )

      assert cycle.workspace_id == workspace.id
    end
  end
end
