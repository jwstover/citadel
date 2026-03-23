defmodule Citadel.Tasks.AgentRunActivityTest do
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
          task_state_id: task_state.id
        },
        actor: user,
        tenant: workspace.id
      )

    {:ok, user: user, workspace: workspace, task: task}
  end

  describe "create_agent_run_activity/2" do
    test "creates an agent run activity with correct attributes", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(agent_run([task_id: task.id], actor: user, tenant: workspace.id))

      activity =
        Tasks.create_agent_run_activity!(
          %{task_id: task.id, agent_run_id: agent_run.id},
          tenant: workspace.id
        )

      assert activity.type == :agent_run
      assert activity.actor_type == :ai
      assert activity.actor_display_name == "Agent"
      assert activity.task_id == task.id
      assert activity.agent_run_id == agent_run.id
      assert activity.workspace_id == workspace.id
    end

    test "inherits workspace_id from task", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(agent_run([task_id: task.id], actor: user, tenant: workspace.id))

      activity =
        Tasks.create_agent_run_activity!(
          %{task_id: task.id, agent_run_id: agent_run.id},
          tenant: workspace.id
        )

      assert activity.workspace_id == workspace.id
      assert activity.workspace_id == task.workspace_id
    end

    test "can load agent_run relationship", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(agent_run([task_id: task.id], actor: user, tenant: workspace.id))

      activity =
        Tasks.create_agent_run_activity!(
          %{task_id: task.id, agent_run_id: agent_run.id},
          tenant: workspace.id
        )

      loaded = Ash.load!(activity, :agent_run, authorize?: false, tenant: workspace.id)
      assert loaded.agent_run.id == agent_run.id
      assert loaded.agent_run.status == :pending
    end

    test "broadcasts PubSub message on create", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(agent_run([task_id: task.id], actor: user, tenant: workspace.id))

      CitadelWeb.Endpoint.subscribe("tasks:task_activities:#{task.id}")

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:task_activities:" <> _,
        event: "create_agent_run_activity"
      }
    end

    test "bypasses authorization (no actor required)", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(agent_run([task_id: task.id], actor: user, tenant: workspace.id))

      activity =
        Tasks.create_agent_run_activity!(
          %{task_id: task.id, agent_run_id: agent_run.id},
          tenant: workspace.id
        )

      assert activity.id
    end
  end

  describe "list_task_activities/2 with agent run activities" do
    test "returns agent run activities alongside comments in chronological order", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      Tasks.create_comment!(
        %{body: "First comment", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      agent_run =
        generate(agent_run([task_id: task.id], actor: user, tenant: workspace.id))

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id
      )

      Tasks.create_comment!(
        %{body: "Second comment", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      activities =
        Tasks.list_task_activities!(task.id, actor: user, tenant: workspace.id)

      assert length(activities) == 3
      assert Enum.at(activities, 0).type == :comment
      assert Enum.at(activities, 0).body == "First comment"
      assert Enum.at(activities, 1).type == :agent_run
      assert Enum.at(activities, 2).type == :comment
      assert Enum.at(activities, 2).body == "Second comment"
    end

    test "agent run activities have nil body", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(agent_run([task_id: task.id], actor: user, tenant: workspace.id))

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id
      )

      activities =
        Tasks.list_task_activities!(task.id, actor: user, tenant: workspace.id)

      assert length(activities) == 1
      activity = hd(activities)
      assert activity.type == :agent_run
      assert is_nil(activity.body)
      assert activity.actor_type == :ai
    end

    test "agent run activity is nilified when agent run is deleted", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(agent_run([task_id: task.id], actor: user, tenant: workspace.id))

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id
      )

      Ash.destroy!(agent_run, authorize?: false, tenant: workspace.id)

      activities =
        Tasks.list_task_activities!(task.id, actor: user, tenant: workspace.id)

      assert length(activities) == 1
      activity = hd(activities)
      assert is_nil(activity.agent_run_id)
    end
  end

  describe "agent run activity cascade" do
    test "agent run activities are deleted when task is destroyed", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      agent_run =
        generate(agent_run([task_id: task.id], actor: user, tenant: workspace.id))

      Tasks.create_agent_run_activity!(
        %{task_id: task.id, agent_run_id: agent_run.id},
        tenant: workspace.id
      )

      Ash.destroy!(task, actor: user, tenant: workspace.id)

      activities =
        Citadel.Tasks.TaskActivity
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert activities == []
    end
  end
end
