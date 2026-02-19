defmodule Citadel.Tasks.TaskActivityInterfacesTest do
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

    {:ok, user: user, workspace: workspace, task: task}
  end

  describe "create_comment/2" do
    test "creates a comment with body and task_id", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activity =
        Tasks.create_comment!(
          %{body: "A new comment", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert activity.body == "A new comment"
      assert activity.type == :comment
      assert activity.actor_type == :user
      assert activity.task_id == task.id
      assert activity.user_id == user.id
      assert activity.workspace_id == workspace.id
    end

    test "workspace member can create a comment", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      member = generate(user())
      add_user_to_workspace(member.id, workspace.id, actor: user)

      activity =
        Tasks.create_comment!(
          %{body: "Member comment", task_id: task.id},
          actor: member,
          tenant: workspace.id
        )

      assert activity.body == "Member comment"
      assert activity.user_id == member.id
    end

    test "non-member cannot create a comment", %{workspace: workspace, task: task} do
      outsider = generate(user())

      assert_raise Ash.Error.Forbidden, fn ->
        Tasks.create_comment!(
          %{body: "Unauthorized", task_id: task.id},
          actor: outsider,
          tenant: workspace.id
        )
      end
    end

    test "broadcasts PubSub message on create", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      CitadelWeb.Endpoint.subscribe("tasks:task_activities:#{task.id}")

      Tasks.create_comment!(
        %{body: "PubSub test", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:task_activities:" <> _,
        event: "create_comment"
      }
    end
  end

  describe "list_task_activities/2" do
    test "returns activities for a task in chronological order", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      for i <- 1..3 do
        Tasks.create_comment!(
          %{body: "Comment #{i}", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
      end

      activities = Tasks.list_task_activities!(task.id, actor: user, tenant: workspace.id)

      assert length(activities) == 3
      bodies = Enum.map(activities, & &1.body)
      assert bodies == ["Comment 1", "Comment 2", "Comment 3"]
    end

    test "returns empty list for task with no activities", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activities = Tasks.list_task_activities!(task.id, actor: user, tenant: workspace.id)
      assert activities == []
    end

    test "only returns activities for the specified task", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      task_state = Tasks.list_task_states!() |> List.first()

      other_task =
        Tasks.create_task!(
          %{
            title: "Other Task #{System.unique_integer([:positive])}",
            task_state_id: task_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_comment!(
        %{body: "On original task", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      Tasks.create_comment!(
        %{body: "On other task", task_id: other_task.id},
        actor: user,
        tenant: workspace.id
      )

      activities = Tasks.list_task_activities!(task.id, actor: user, tenant: workspace.id)

      assert length(activities) == 1
      assert hd(activities).body == "On original task"
    end
  end

  describe "destroy_comment/2" do
    test "author can destroy their own comment", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activity =
        Tasks.create_comment!(
          %{body: "To delete", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert :ok = Tasks.destroy_comment!(activity, actor: user, tenant: workspace.id)

      activities = Tasks.list_task_activities!(task.id, actor: user, tenant: workspace.id)
      assert activities == []
    end

    test "non-author cannot destroy another user's comment", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      member = generate(user())
      add_user_to_workspace(member.id, workspace.id, actor: user)

      activity =
        Tasks.create_comment!(
          %{body: "Protected comment", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert_raise Ash.Error.Forbidden, fn ->
        Tasks.destroy_comment!(activity, actor: member, tenant: workspace.id)
      end
    end

    test "broadcasts PubSub message on destroy", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activity =
        Tasks.create_comment!(
          %{body: "To delete", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      CitadelWeb.Endpoint.subscribe("tasks:task_activities:#{task.id}")

      Tasks.destroy_comment!(activity, actor: user, tenant: workspace.id)

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:task_activities:" <> _,
        event: "destroy_comment"
      }
    end
  end
end
