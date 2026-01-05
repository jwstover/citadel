defmodule Citadel.Tasks.Validations.NoCircularDependencyTest do
  use Citadel.DataCase

  alias Citadel.Tasks

  setup do
    todo_state = Tasks.create_task_state!(%{name: "Todo", order: 1, is_complete: false}, authorize?: false)

    Tasks.create_task_state!(%{name: "In Progress", order: 2, is_complete: false},
      authorize?: false
    )

    Tasks.create_task_state!(%{name: "Complete", order: 3, is_complete: true}, authorize?: false)

    user = generate(user())
    workspace = generate(workspace([], actor: user))
    %{user: user, workspace: workspace, todo_state: todo_state}
  end

  describe "NoCircularDependency validation" do
    test "prevents self-reference (A→A)", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      assert {:error, %Ash.Error.Invalid{} = error} =
               Tasks.create_task_dependency(
                 %{task_id: task_a.id, depends_on_task_id: task_a.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert Exception.message(error) =~ "circular dependency"
    end

    test "prevents direct cycle (A→B, then B→A)", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_b = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_b.id},
        actor: user,
        tenant: workspace.id
      )

      assert {:error, %Ash.Error.Invalid{} = error} =
               Tasks.create_task_dependency(
                 %{task_id: task_b.id, depends_on_task_id: task_a.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert Exception.message(error) =~ "circular dependency"
    end

    test "prevents transitive cycle (A→B→C, then C→A)", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_b = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_c = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_b.id},
        actor: user,
        tenant: workspace.id
      )

      Tasks.create_task_dependency!(
        %{task_id: task_b.id, depends_on_task_id: task_c.id},
        actor: user,
        tenant: workspace.id
      )

      assert {:error, %Ash.Error.Invalid{} = error} =
               Tasks.create_task_dependency(
                 %{task_id: task_c.id, depends_on_task_id: task_a.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert Exception.message(error) =~ "circular dependency"
    end

    test "prevents long chain cycle (A→B→C→D→E, then E→A)", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_b = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_c = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_d = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_e = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_b.id},
        actor: user,
        tenant: workspace.id
      )

      Tasks.create_task_dependency!(
        %{task_id: task_b.id, depends_on_task_id: task_c.id},
        actor: user,
        tenant: workspace.id
      )

      Tasks.create_task_dependency!(
        %{task_id: task_c.id, depends_on_task_id: task_d.id},
        actor: user,
        tenant: workspace.id
      )

      Tasks.create_task_dependency!(
        %{task_id: task_d.id, depends_on_task_id: task_e.id},
        actor: user,
        tenant: workspace.id
      )

      assert {:error, %Ash.Error.Invalid{} = error} =
               Tasks.create_task_dependency(
                 %{task_id: task_e.id, depends_on_task_id: task_a.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert Exception.message(error) =~ "circular dependency"
    end

    test "allows valid chain (A→B→C)", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_b = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_c = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_a.id, depends_on_task_id: task_b.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_b.id, depends_on_task_id: task_c.id},
                 actor: user,
                 tenant: workspace.id
               )
    end

    test "allows diamond pattern (A→B, A→C, B→D, C→D)", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_b = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_c = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_d = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_a.id, depends_on_task_id: task_b.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_a.id, depends_on_task_id: task_c.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_b.id, depends_on_task_id: task_d.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_c.id, depends_on_task_id: task_d.id},
                 actor: user,
                 tenant: workspace.id
               )
    end

    test "allows complex graph without cycles", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_b = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_c = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_d = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_e = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_a.id, depends_on_task_id: task_b.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_a.id, depends_on_task_id: task_c.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_b.id, depends_on_task_id: task_d.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_c.id, depends_on_task_id: task_e.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert {:ok, _} =
               Tasks.create_task_dependency(
                 %{task_id: task_d.id, depends_on_task_id: task_e.id},
                 actor: user,
                 tenant: workspace.id
               )
    end
  end
end
