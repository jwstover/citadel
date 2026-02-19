defmodule Citadel.Tasks.TaskActivityTest do
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

  describe "create" do
    test "creates a comment activity with valid attributes", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "This is a comment", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert activity.body == "This is a comment"
      assert activity.type == :comment
      assert activity.actor_type == :user
      assert activity.task_id == task.id
      assert activity.user_id == user.id
      assert activity.workspace_id == workspace.id
      assert activity.metadata == %{}
    end

    test "inherits workspace_id from task", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Test", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert activity.workspace_id == workspace.id
      assert activity.workspace_id == task.workspace_id
    end

    test "sets user from actor via relate_actor", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Test", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert activity.user_id == user.id
    end

    test "allows nil body", %{user: user, workspace: workspace, task: task} do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert is_nil(activity.body)
    end

    test "allows custom metadata", %{user: user, workspace: workspace, task: task} do
      metadata = %{"old_state" => "To Do", "new_state" => "In Progress"}

      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "State changed", task_id: task.id, metadata: metadata},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert activity.metadata == metadata
    end

    test "allows setting actor_type to :system", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{
            body: "Auto-generated",
            task_id: task.id,
            actor_type: :system,
            actor_display_name: "System"
          },
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert activity.actor_type == :system
      assert activity.actor_display_name == "System"
    end

    test "allows setting actor_type to :ai", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{
            body: "AI suggestion",
            task_id: task.id,
            actor_type: :ai,
            actor_display_name: "Claude"
          },
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert activity.actor_type == :ai
      assert activity.actor_display_name == "Claude"
    end

    test "errors when task_id is invalid", %{user: user, workspace: workspace} do
      fake_task_id = Ash.UUID.generate()

      assert_raise Ash.Error.Invalid, fn ->
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Test", task_id: fake_task_id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)
      end
    end
  end

  describe "read" do
    test "can read activities for a task", %{user: user, workspace: workspace, task: task} do
      for i <- 1..3 do
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Comment #{i}", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)
      end

      activities =
        Citadel.Tasks.TaskActivity
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert length(activities) == 3
    end

    test "workspace owner can read activities", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      Citadel.Tasks.TaskActivity
      |> Ash.Changeset.for_create(
        :create,
        %{body: "Test", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )
      |> Ash.create!(authorize?: false)

      activities =
        Citadel.Tasks.TaskActivity
        |> Ash.read!(actor: user, tenant: workspace.id)

      assert length(activities) == 1
    end

    test "workspace member can read activities", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      member = generate(user())
      add_user_to_workspace(member.id, workspace.id, actor: user)

      Citadel.Tasks.TaskActivity
      |> Ash.Changeset.for_create(
        :create,
        %{body: "Test", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )
      |> Ash.create!(authorize?: false)

      activities =
        Citadel.Tasks.TaskActivity
        |> Ash.read!(actor: member, tenant: workspace.id)

      assert length(activities) == 1
    end

    test "non-member cannot read activities", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      outsider = generate(user())

      Citadel.Tasks.TaskActivity
      |> Ash.Changeset.for_create(
        :create,
        %{body: "Secret", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )
      |> Ash.create!(authorize?: false)

      activities =
        Citadel.Tasks.TaskActivity
        |> Ash.read!(actor: outsider, tenant: workspace.id)

      assert activities == []
    end
  end

  describe "destroy" do
    test "can destroy an activity", %{user: user, workspace: workspace, task: task} do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "To delete", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert :ok = Ash.destroy!(activity, actor: user, tenant: workspace.id)

      activities =
        Citadel.Tasks.TaskActivity
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert activities == []
    end

    test "non-member cannot destroy activities", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      outsider = generate(user())
      outsider_workspace = generate(workspace([], actor: outsider))

      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Protected", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert_raise Ash.Error.Forbidden, fn ->
        Ash.destroy!(activity, actor: outsider, tenant: outsider_workspace.id)
      end
    end
  end

  describe "cascade delete" do
    test "activities are deleted when task is destroyed", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      for i <- 1..3 do
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Comment #{i}", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)
      end

      activities =
        Citadel.Tasks.TaskActivity
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert length(activities) == 3

      Ash.destroy!(task, actor: user, tenant: workspace.id)

      activities =
        Citadel.Tasks.TaskActivity
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert activities == []
    end
  end

  describe "relationships" do
    test "can load task relationship", %{user: user, workspace: workspace, task: task} do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Test", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      loaded = Ash.load!(activity, :task, authorize?: false, tenant: workspace.id)
      assert loaded.task.id == task.id
    end

    test "can load user relationship", %{user: user, workspace: workspace, task: task} do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Test", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      loaded = Ash.load!(activity, :user, authorize?: false, tenant: workspace.id)
      assert loaded.user.id == user.id
    end

    test "can load activities from task", %{user: user, workspace: workspace, task: task} do
      Citadel.Tasks.TaskActivity
      |> Ash.Changeset.for_create(
        :create,
        %{body: "Comment 1", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )
      |> Ash.create!(authorize?: false)

      Citadel.Tasks.TaskActivity
      |> Ash.Changeset.for_create(
        :create,
        %{body: "Comment 2", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )
      |> Ash.create!(authorize?: false)

      loaded = Ash.load!(task, :activities, authorize?: false, tenant: workspace.id)
      assert length(loaded.activities) == 2
      bodies = Enum.map(loaded.activities, & &1.body)
      assert "Comment 1" in bodies
      assert "Comment 2" in bodies
    end
  end

  describe "defaults" do
    test "type defaults to :comment", %{user: user, workspace: workspace, task: task} do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Test", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert activity.type == :comment
    end

    test "actor_type defaults to :user", %{user: user, workspace: workspace, task: task} do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Test", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert activity.actor_type == :user
    end

    test "metadata defaults to empty map", %{user: user, workspace: workspace, task: task} do
      activity =
        Citadel.Tasks.TaskActivity
        |> Ash.Changeset.for_create(
          :create,
          %{body: "Test", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )
        |> Ash.create!(authorize?: false)

      assert activity.metadata == %{}
    end
  end
end
