defmodule Citadel.Tasks.TaskPubSubTest do
  @moduledoc """
  Tests for PubSub real-time updates on tasks.

  These tests verify that:
  - Task creates/updates/destroys broadcast to the workspace topic
  - Task updates also broadcast to the task-specific topic
  - Sub-task changes broadcast to the parent task's children topic
  - Workspace isolation is maintained
  """
  use Citadel.DataCase, async: true

  alias Citadel.Tasks

  setup do
    owner = generate(user())
    workspace = generate(workspace([], actor: owner))
    task_state = Tasks.list_task_states!() |> List.first()

    {:ok, owner: owner, workspace: workspace, task_state: task_state}
  end

  describe "workspace topic broadcasts" do
    test "task creation broadcasts to workspace topic", context do
      %{owner: owner, workspace: workspace, task_state: task_state} = context

      CitadelWeb.Endpoint.subscribe("tasks:tasks:#{workspace.id}")

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id],
            actor: owner,
            tenant: workspace.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:tasks:" <> topic_workspace_id,
        event: "create",
        payload: payload
      }

      assert topic_workspace_id == workspace.id
      assert payload.id == task.id
      assert payload.title == task.title
    end

    test "task update broadcasts to workspace topic", context do
      %{owner: owner, workspace: workspace, task_state: task_state} = context

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id],
            actor: owner,
            tenant: workspace.id
          )
        )

      CitadelWeb.Endpoint.subscribe("tasks:tasks:#{workspace.id}")

      Tasks.update_task!(task.id, %{title: "Updated Title"},
        actor: owner,
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:tasks:" <> _,
        event: "update",
        payload: payload
      }

      assert payload.id == task.id
      assert payload.title == "Updated Title"
    end

    test "task destroy broadcasts to workspace topic", context do
      %{owner: owner, workspace: workspace, task_state: task_state} = context

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id],
            actor: owner,
            tenant: workspace.id
          )
        )

      CitadelWeb.Endpoint.subscribe("tasks:tasks:#{workspace.id}")

      Tasks.destroy_task!(task, actor: owner, tenant: workspace.id)

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:tasks:" <> _,
        event: "destroy",
        payload: payload
      }

      assert payload.id == task.id
      assert payload.task_state_id == task.task_state_id
      assert payload.action == :destroy
    end
  end

  describe "task-specific topic broadcasts" do
    test "task update broadcasts to task-specific topic", context do
      %{owner: owner, workspace: workspace, task_state: task_state} = context

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id],
            actor: owner,
            tenant: workspace.id
          )
        )

      CitadelWeb.Endpoint.subscribe("tasks:task:#{task.id}")

      Tasks.update_task!(task.id, %{title: "Updated Title"},
        actor: owner,
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:task:" <> topic_task_id,
        event: "update",
        payload: payload
      }

      assert topic_task_id == task.id
      assert payload.id == task.id
      assert payload.title == "Updated Title"
    end
  end

  describe "sub-task (parent children) topic broadcasts" do
    test "sub-task creation broadcasts to parent children topic", context do
      %{owner: owner, workspace: workspace, task_state: task_state} = context

      parent_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id],
            actor: owner,
            tenant: workspace.id
          )
        )

      CitadelWeb.Endpoint.subscribe("tasks:task_children:#{parent_task.id}")

      sub_task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: task_state.id,
              parent_task_id: parent_task.id
            ],
            actor: owner,
            tenant: workspace.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:task_children:" <> topic_parent_id,
        event: "create",
        payload: payload
      }

      assert topic_parent_id == parent_task.id
      assert payload.id == sub_task.id
      assert payload.parent_task_id == parent_task.id
    end

    test "sub-task update broadcasts to parent children topic", context do
      %{owner: owner, workspace: workspace, task_state: task_state} = context

      parent_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id],
            actor: owner,
            tenant: workspace.id
          )
        )

      sub_task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: task_state.id,
              parent_task_id: parent_task.id
            ],
            actor: owner,
            tenant: workspace.id
          )
        )

      CitadelWeb.Endpoint.subscribe("tasks:task_children:#{parent_task.id}")

      Tasks.update_task!(sub_task.id, %{title: "Updated Sub-task"},
        actor: owner,
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:task_children:" <> topic_parent_id,
        event: "update",
        payload: payload
      }

      assert topic_parent_id == parent_task.id
      assert payload.id == sub_task.id
      assert payload.title == "Updated Sub-task"
    end

    test "sub-task destroy broadcasts to parent children topic", context do
      %{owner: owner, workspace: workspace, task_state: task_state} = context

      parent_task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id],
            actor: owner,
            tenant: workspace.id
          )
        )

      sub_task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: task_state.id,
              parent_task_id: parent_task.id
            ],
            actor: owner,
            tenant: workspace.id
          )
        )

      CitadelWeb.Endpoint.subscribe("tasks:task_children:#{parent_task.id}")

      Tasks.destroy_task!(sub_task, actor: owner, tenant: workspace.id)

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:task_children:" <> topic_parent_id,
        event: "destroy",
        payload: payload
      }

      assert topic_parent_id == parent_task.id
      assert payload.id == sub_task.id
      assert payload.action == :destroy
    end
  end

  describe "workspace isolation" do
    test "tasks in different workspaces don't cross-contaminate" do
      owner1 = generate(user())
      workspace1 = generate(workspace([], actor: owner1))

      owner2 = generate(user())
      workspace2 = generate(workspace([], actor: owner2))

      task_state = Tasks.list_task_states!() |> List.first()

      CitadelWeb.Endpoint.subscribe("tasks:tasks:#{workspace1.id}")

      _task2 =
        generate(
          task(
            [workspace_id: workspace2.id, task_state_id: task_state.id],
            actor: owner2,
            tenant: workspace2.id
          )
        )

      refute_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:tasks:" <> ^workspace1
      }
    end

    test "tasks in same workspace use same topic", context do
      %{owner: owner, workspace: workspace, task_state: task_state} = context

      CitadelWeb.Endpoint.subscribe("tasks:tasks:#{workspace.id}")

      task1 =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id, title: "Task 1"],
            actor: owner,
            tenant: workspace.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:tasks:" <> ws1_id_first,
        event: "create",
        payload: %{id: task1_id}
      }

      assert ws1_id_first == workspace.id
      assert task1_id == task1.id

      task2 =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id, title: "Task 2"],
            actor: owner,
            tenant: workspace.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:tasks:" <> ws1_id_second,
        event: "create",
        payload: %{id: task2_id}
      }

      assert ws1_id_second == workspace.id
      assert task2_id == task2.id
      assert ws1_id_first == ws1_id_second
    end
  end

  describe "payload transformation" do
    test "create payload contains expected fields", context do
      %{owner: owner, workspace: workspace, task_state: task_state} = context

      CitadelWeb.Endpoint.subscribe("tasks:tasks:#{workspace.id}")

      task =
        generate(
          task(
            [
              workspace_id: workspace.id,
              task_state_id: task_state.id,
              title: "Test Task",
              description: "Description",
              priority: :high,
              due_date: ~D[2025-12-31]
            ],
            actor: owner,
            tenant: workspace.id
          )
        )

      assert_receive %Phoenix.Socket.Broadcast{
        event: "create",
        payload: payload
      }

      assert payload.id == task.id
      assert payload.human_id == task.human_id
      assert payload.title == "Test Task"
      assert payload.description == "Description"
      assert payload.task_state_id == task_state.id
      assert payload.priority == :high
      assert payload.due_date == ~D[2025-12-31]
      assert payload.workspace_id == workspace.id
      assert is_nil(payload.parent_task_id)
    end

    test "destroy payload contains minimal fields for efficient handling", context do
      %{owner: owner, workspace: workspace, task_state: task_state} = context

      task =
        generate(
          task(
            [workspace_id: workspace.id, task_state_id: task_state.id],
            actor: owner,
            tenant: workspace.id
          )
        )

      CitadelWeb.Endpoint.subscribe("tasks:tasks:#{workspace.id}")

      Tasks.destroy_task!(task, actor: owner, tenant: workspace.id)

      assert_receive %Phoenix.Socket.Broadcast{
        event: "destroy",
        payload: payload
      }

      assert payload.id == task.id
      assert payload.task_state_id == task.task_state_id
      assert payload.action == :destroy
      refute Map.has_key?(payload, :title)
      refute Map.has_key?(payload, :description)
    end
  end
end
