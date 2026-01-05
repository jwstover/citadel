defmodule Citadel.Tasks.TaskRelationshipsTest do
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

  describe "dependencies relationship" do
    test "loads tasks that this task depends on", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_b = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_c = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_b.id},
        actor: user,
        tenant: workspace.id
      )

      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_c.id},
        actor: user,
        tenant: workspace.id
      )

      task_a = Tasks.get_task!(task_a.id, actor: user, load: [:dependencies])

      assert length(task_a.dependencies) == 2
      assert Enum.any?(task_a.dependencies, &(&1.id == task_b.id))
      assert Enum.any?(task_a.dependencies, &(&1.id == task_c.id))
    end
  end

  describe "dependents relationship" do
    test "loads tasks that depend on this task", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_b = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_c = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      Tasks.create_task_dependency!(
        %{task_id: task_b.id, depends_on_task_id: task_a.id},
        actor: user,
        tenant: workspace.id
      )

      Tasks.create_task_dependency!(
        %{task_id: task_c.id, depends_on_task_id: task_a.id},
        actor: user,
        tenant: workspace.id
      )

      task_a = Tasks.get_task!(task_a.id, actor: user, load: [:dependents])

      assert length(task_a.dependents) == 2
      assert Enum.any?(task_a.dependents, &(&1.id == task_b.id))
      assert Enum.any?(task_a.dependents, &(&1.id == task_c.id))
    end
  end

  describe "blocked? calculation" do
    test "returns false when task has no dependencies", %{user: user, workspace: workspace, todo_state: todo_state} do
      task = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      task = Tasks.get_task!(task.id, actor: user, load: [:blocked?])

      refute task.blocked?
    end

    test "returns false when all dependencies are complete", %{user: user, workspace: workspace, todo_state: todo_state} do
      complete_state =
        Tasks.list_task_states!(authorize?: false)
        |> Enum.find(&(&1.is_complete == true))

      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      task_b =
        generate(
          task([task_state_id: complete_state.id], actor: user, tenant: workspace.id)
        )

      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_b.id},
        actor: user,
        tenant: workspace.id
      )

      task_a =
        Tasks.get_task!(task_a.id, actor: user, load: [blocked?: [dependencies: [:task_state]]])

      refute task_a.blocked?
    end

    test "returns true when any dependency is incomplete", %{user: user, workspace: workspace, todo_state: todo_state} do
      incomplete_state =
        Tasks.list_task_states!(authorize?: false)
        |> Enum.find(&(&1.is_complete == false))

      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      task_b =
        generate(
          task([task_state_id: incomplete_state.id], actor: user, tenant: workspace.id)
        )

      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_b.id},
        actor: user,
        tenant: workspace.id
      )

      task_a =
        Tasks.get_task!(task_a.id, actor: user, load: [blocked?: [dependencies: [:task_state]]])

      assert task_a.blocked?
    end
  end

  describe "blocking_count calculation" do
    test "returns 0 when task has no dependencies", %{user: user, workspace: workspace, todo_state: todo_state} do
      task = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      task = Tasks.get_task!(task.id, actor: user, load: [:blocking_count])

      assert task.blocking_count == 0
    end

    test "returns count of incomplete dependencies", %{user: user, workspace: workspace, todo_state: todo_state} do
      complete_state =
        Tasks.list_task_states!(authorize?: false)
        |> Enum.find(&(&1.is_complete == true))

      incomplete_state =
        Tasks.list_task_states!(authorize?: false)
        |> Enum.find(&(&1.is_complete == false))

      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      task_b =
        generate(
          task([task_state_id: incomplete_state.id], actor: user, tenant: workspace.id)
        )

      task_c =
        generate(
          task([task_state_id: incomplete_state.id], actor: user, tenant: workspace.id)
        )

      task_d =
        generate(
          task([task_state_id: complete_state.id], actor: user, tenant: workspace.id)
        )

      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_b.id},
        actor: user,
        tenant: workspace.id
      )

      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_c.id},
        actor: user,
        tenant: workspace.id
      )

      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_d.id},
        actor: user,
        tenant: workspace.id
      )

      task_a =
        Tasks.get_task!(task_a.id,
          actor: user,
          load: [blocking_count: [dependencies: [:task_state]]]
        )

      assert task_a.blocking_count == 2
    end
  end
end
