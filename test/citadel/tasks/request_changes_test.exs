defmodule Citadel.Tasks.RequestChangesTest do
  use Citadel.DataCase, async: true

  alias Citadel.Tasks

  setup do
    require Ash.Query

    user = generate(user())
    workspace = generate(workspace([], actor: user))

    [in_review_state] =
      Citadel.Tasks.TaskState
      |> Ash.Query.filter(name == "In Review")
      |> Ash.read!(authorize?: false)

    [in_progress_state] =
      Citadel.Tasks.TaskState
      |> Ash.Query.filter(name == "In Progress")
      |> Ash.read!(authorize?: false)

    todo_state =
      Tasks.create_task_state!(%{
        name: "To Do #{System.unique_integer([:positive])}",
        order: 1
      })

    task =
      Tasks.create_task!(
        %{
          title: "Test Task #{System.unique_integer([:positive])}",
          task_state_id: in_review_state.id,
          workspace_id: workspace.id
        },
        actor: user,
        tenant: workspace.id
      )

    {:ok,
     user: user,
     workspace: workspace,
     task: task,
     in_review_state: in_review_state,
     in_progress_state: in_progress_state,
     todo_state: todo_state}
  end

  describe "create_request_changes_comment/2" do
    test "creates a change_request comment", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activity =
        Tasks.create_request_changes_comment!(
          %{body: "Please fix the tests", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      assert activity.body == "Please fix the tests"
      assert activity.type == :change_request
      assert activity.actor_type == :user
      assert activity.task_id == task.id
      assert activity.user_id == user.id
      assert activity.workspace_id == workspace.id
    end

    test "creates a changes_requested work item", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      activity =
        Tasks.create_request_changes_comment!(
          %{body: "Needs rework", task_id: task.id},
          actor: user,
          tenant: workspace.id
        )

      require Ash.Query

      [work_item] =
        Citadel.Tasks.AgentWorkItem
        |> Ash.Query.filter(task_id == ^task.id)
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert work_item.type == :changes_requested
      assert work_item.status == :pending
      assert work_item.comment_id == activity.id
    end

    test "transitions task from In Review to In Progress", %{
      user: user,
      workspace: workspace,
      task: task,
      in_progress_state: in_progress_state
    } do
      Tasks.create_request_changes_comment!(
        %{body: "Fix this", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      updated_task = Tasks.get_task!(task.id, tenant: workspace.id, authorize?: false)
      assert updated_task.task_state_id == in_progress_state.id
    end

    test "does not transition task if not in In Review state", %{
      user: user,
      workspace: workspace,
      todo_state: todo_state
    } do
      task =
        Tasks.create_task!(
          %{
            title: "Todo Task #{System.unique_integer([:positive])}",
            task_state_id: todo_state.id,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      Tasks.create_request_changes_comment!(
        %{body: "Fix this", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      updated_task = Tasks.get_task!(task.id, tenant: workspace.id, authorize?: false)
      assert updated_task.task_state_id == todo_state.id
    end

    test "is resilient to duplicate work items", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      Tasks.create_request_changes_comment!(
        %{body: "First request", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      require Ash.Query

      [first_item] =
        Citadel.Tasks.AgentWorkItem
        |> Ash.Query.filter(task_id == ^task.id and status in [:pending, :claimed])
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      Citadel.Tasks.cancel_agent_work_item!(first_item, authorize?: false, tenant: workspace.id)

      Tasks.create_request_changes_comment!(
        %{body: "Second request", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      items =
        Citadel.Tasks.AgentWorkItem
        |> Ash.Query.filter(task_id == ^task.id)
        |> Ash.read!(authorize?: false, tenant: workspace.id)

      assert length(items) == 2
    end

    test "workspace member can request changes", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      member = generate(user())
      add_user_to_workspace(member.id, workspace.id, actor: user)

      activity =
        Tasks.create_request_changes_comment!(
          %{body: "Member feedback", task_id: task.id},
          actor: member,
          tenant: workspace.id
        )

      assert activity.type == :change_request
      assert activity.user_id == member.id
    end

    test "non-member cannot request changes", %{workspace: workspace, task: task} do
      outsider = generate(user())

      assert_raise Ash.Error.Forbidden, fn ->
        Tasks.create_request_changes_comment!(
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

      Tasks.create_request_changes_comment!(
        %{body: "PubSub test", task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:task_activities:" <> _,
        event: "create_request_changes_comment"
      }
    end
  end
end
