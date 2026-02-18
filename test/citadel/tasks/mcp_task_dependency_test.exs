defmodule Citadel.Tasks.McpTaskDependencyTest do
  use Citadel.DataCase

  alias Citadel.Tasks

  setup do
    all_states = Tasks.list_task_states!(authorize?: false)
    incomplete_states = Enum.filter(all_states, &(&1.is_complete == false))

    todo_state = Enum.at(incomplete_states, 0)

    %{todo_state: todo_state}
  end

  describe "MCP create_task_dependency tool" do
    setup context do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      task_a =
        generate(task([task_state_id: context.todo_state.id], actor: user, tenant: workspace.id))

      task_b =
        generate(task([task_state_id: context.todo_state.id], actor: user, tenant: workspace.id))

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

    test "fails for self-referential dependency", %{
      user: user,
      workspace: workspace,
      task_a: task_a
    } do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Tasks.create_task_dependency(
                 %{task_id: task_a.id, depends_on_task_id: task_a.id},
                 actor: user,
                 tenant: workspace.id
               )

      assert Exception.message(error) =~ "a task cannot depend on itself"
    end

    test "fails for circular dependency", %{
      user: user,
      workspace: workspace,
      task_a: task_a,
      task_b: task_b,
      todo_state: todo_state
    } do
      task_c =
        generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

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

      assert Exception.message(error) =~ "circular"
    end
  end

  describe "MCP delete_task_dependency tool" do
    setup context do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      task_a =
        generate(task([task_state_id: context.todo_state.id], actor: user, tenant: workspace.id))

      task_b =
        generate(task([task_state_id: context.todo_state.id], actor: user, tenant: workspace.id))

      %{user: user, workspace: workspace, task_a: task_a, task_b: task_b}
    end

    test "removes an existing dependency", %{
      user: user,
      workspace: workspace,
      task_a: task_a,
      task_b: task_b
    } do
      dependency =
        Tasks.create_task_dependency!(
          %{task_id: task_a.id, depends_on_task_id: task_b.id},
          actor: user,
          tenant: workspace.id
        )

      assert :ok = Tasks.destroy_task_dependency(dependency, actor: user)

      dependencies = Tasks.list_task_dependencies!(task_a.id, actor: user, tenant: workspace.id)
      assert dependencies == []
    end
  end

  describe "Task create with dependencies argument" do
    setup context do
      user = generate(user())
      workspace = generate(workspace([], actor: user))
      %{user: user, workspace: workspace, todo_state: context.todo_state}
    end

    test "creates a task with initial dependencies", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      dep_task_1 =
        generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      dep_task_2 =
        generate(task([task_state_id: todo_state.id], actor: user, tenant: workspace.id))

      assert {:ok, task} =
               Tasks.create_task(
                 %{
                   title: "Task with dependencies",
                   task_state_id: todo_state.id,
                   workspace_id: workspace.id,
                   dependencies: [dep_task_1.id, dep_task_2.id]
                 },
                 actor: user,
                 tenant: workspace.id
               )

      task = Ash.load!(task, [:dependencies], authorize?: false)

      assert length(task.dependencies) == 2
      dependency_ids = Enum.map(task.dependencies, & &1.id)
      assert dep_task_1.id in dependency_ids
      assert dep_task_2.id in dependency_ids
    end

    test "creates a task with empty dependencies array", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      assert {:ok, task} =
               Tasks.create_task(
                 %{
                   title: "Task without dependencies",
                   task_state_id: todo_state.id,
                   workspace_id: workspace.id,
                   dependencies: []
                 },
                 actor: user,
                 tenant: workspace.id
               )

      task = Ash.load!(task, [:dependencies], authorize?: false)
      assert task.dependencies == []
    end

    test "creates a task without dependencies argument", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      assert {:ok, task} =
               Tasks.create_task(
                 %{
                   title: "Task no deps arg",
                   task_state_id: todo_state.id,
                   workspace_id: workspace.id
                 },
                 actor: user,
                 tenant: workspace.id
               )

      task = Ash.load!(task, [:dependencies], authorize?: false)
      assert task.dependencies == []
    end
  end
end
