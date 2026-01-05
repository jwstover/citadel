defmodule Citadel.Tasks.TaskDependencyTest do
  use Citadel.DataCase

  alias Citadel.Tasks

  setup do
    todo_state =
      Tasks.create_task_state!(%{name: "Todo", order: 1, is_complete: false}, authorize?: false)

    in_progress_state =
      Tasks.create_task_state!(%{name: "In Progress", order: 2, is_complete: false},
        authorize?: false
      )

    complete_state =
      Tasks.create_task_state!(%{name: "Complete", order: 3, is_complete: true},
        authorize?: false
      )

    %{
      todo_state: todo_state,
      in_progress_state: in_progress_state,
      complete_state: complete_state
    }
  end

  describe "create_task_dependency/1" do
    setup context do
      user = generate(user())
      workspace = generate(workspace([], actor: user))
      task_a = generate(task([task_state_id: context.todo_state.id], actor: user, tenant: workspace.id))
      task_b = generate(task([task_state_id: context.todo_state.id], actor: user, tenant: workspace.id))

      %{user: user, workspace: workspace, task_a: task_a, task_b: task_b}
    end

    test "creates a valid dependency between two tasks", %{
      user: user,
      workspace: workspace,
      task_a: task_a,
      task_b: task_b
    } do
      assert {:ok, dependency} =
               Tasks.create_task_dependency(
                 %{task_id: task_a.id, depends_on_task_id: task_b.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert dependency.task_id == task_a.id
      assert dependency.depends_on_task_id == task_b.id
    end

    test "prevents self-referential dependency", %{user: user, workspace: workspace, task_a: task_a} do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Tasks.create_task_dependency(
                 %{task_id: task_a.id, depends_on_task_id: task_a.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert Exception.message(error) =~ "a task cannot depend on itself"
    end

    test "prevents duplicate dependencies", %{
      user: user,
      workspace: workspace,
      task_a: task_a,
      task_b: task_b
    } do
      Tasks.create_task_dependency!(
        %{task_id: task_a.id, depends_on_task_id: task_b.id},
        actor: user,
        tenant: workspace.id
      )

      assert {:error, %Ash.Error.Invalid{}} =
               Tasks.create_task_dependency(
                 %{task_id: task_a.id, depends_on_task_id: task_b.id},
                 actor: user,
                 tenant: workspace.id
               )
    end

    test "deletes dependency when task is deleted", %{
      user: user,
      workspace: workspace,
      task_a: task_a,
      task_b: task_b
    } do
      _dependency =
        Tasks.create_task_dependency!(
          %{task_id: task_a.id, depends_on_task_id: task_b.id},
          actor: user,
          tenant: workspace.id
        )

      Tasks.destroy_task!(task_a, actor: user)

      # Try to list dependencies for the deleted task - should return empty
      dependencies = Tasks.list_task_dependencies!(task_a.id, actor: user, tenant: workspace.id)
      assert dependencies == []
    end

    test "deletes dependency when depends_on task is deleted", %{
      user: user,
      workspace: workspace,
      task_a: task_a,
      task_b: task_b
    } do
      _dependency =
        Tasks.create_task_dependency!(
          %{task_id: task_a.id, depends_on_task_id: task_b.id},
          actor: user,
          tenant: workspace.id
        )

      Tasks.destroy_task!(task_b, actor: user)

      # Dependency should be deleted
      dependencies = Tasks.list_task_dependencies!(task_a.id, actor: user, tenant: workspace.id)
      assert dependencies == []
    end
  end

  describe "add_task_dependency_by_human_id/2" do
    setup context do
      user = generate(user())
      workspace = generate(workspace([], actor: user))
      %{user: user, workspace: workspace, todo_state: context.todo_state}
    end

    test "creates dependency using human_id", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))
      task_b = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      assert {:ok, dependency} =
               Tasks.add_task_dependency_by_human_id(
                 task_a.id,
                 task_b.human_id,
                 actor: user,
                 tenant: workspace.id
               )

      assert dependency.task_id == task_a.id
      assert dependency.depends_on_task_id == task_b.id
    end

    test "returns error for invalid human_id", %{user: user, workspace: workspace, todo_state: todo_state} do
      task_a = generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      assert {:error, %Ash.Error.Invalid{} = error} =
               Tasks.add_task_dependency_by_human_id(
                 task_a.id,
                 "INVALID-999",
                 actor: user,
                 tenant: workspace.id
               )

      assert Exception.message(error) =~ "task not found"
    end
  end

  describe "list_task_dependencies/1" do
    setup context do
      user = generate(user())
      workspace = generate(workspace([], actor: user))
      %{user: user, workspace: workspace, todo_state: context.todo_state}
    end

    test "returns dependencies for a task", %{user: user, workspace: workspace, todo_state: todo_state} do
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

      dependencies = Tasks.list_task_dependencies!(task_a.id, actor: user, tenant: workspace.id)

      assert length(dependencies) == 2
      assert Enum.any?(dependencies, &(&1.depends_on_task_id == task_b.id))
      assert Enum.any?(dependencies, &(&1.depends_on_task_id == task_c.id))
    end
  end

  describe "list_task_dependents/1" do
    setup context do
      user = generate(user())
      workspace = generate(workspace([], actor: user))
      %{user: user, workspace: workspace, todo_state: context.todo_state}
    end

    test "returns tasks that depend on this task", %{user: user, workspace: workspace, todo_state: todo_state} do
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

      dependents = Tasks.list_task_dependents!(task_a.id, actor: user, tenant: workspace.id)

      assert length(dependents) == 2
      assert Enum.any?(dependents, &(&1.task_id == task_b.id))
      assert Enum.any?(dependents, &(&1.task_id == task_c.id))
    end
  end
end
