defmodule Citadel.Tasks.TaskSummaryTest do
  use Citadel.DataCase, async: true

  alias Ash.Resource.Info
  alias Citadel.Tasks
  alias Citadel.Tasks.TaskSummary

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
          workspace_id: workspace.id,
          priority: :high,
          due_date: ~D[2026-04-01]
        },
        actor: user,
        tenant: workspace.id
      )

    {:ok, user: user, workspace: workspace, task_state: task_state, task: task}
  end

  describe "list_task_summaries/1" do
    test "returns task summaries with public attributes", %{
      user: user,
      workspace: workspace,
      task: task
    } do
      [summary] =
        Tasks.list_task_summaries!(
          tenant: workspace.id,
          actor: user,
          authorize?: false
        )

      assert summary.id == task.id
      assert summary.human_id == task.human_id
      assert summary.title == task.title
      assert summary.priority == :high
      assert summary.due_date == ~D[2026-04-01]
    end

    test "loads task_state relationship", %{
      user: user,
      workspace: workspace,
      task_state: task_state
    } do
      [summary] =
        Tasks.list_task_summaries!(
          tenant: workspace.id,
          actor: user,
          authorize?: false,
          load: [:task_state]
        )

      assert summary.task_state.id == task_state.id
      assert summary.task_state.name == task_state.name
    end

    test "enforces read policy - denies access to non-members", %{workspace: workspace} do
      other_user = generate(user())

      assert [] ==
               Tasks.list_task_summaries!(
                 tenant: workspace.id,
                 actor: other_user
               )
    end

    test "allows workspace owner to read", %{user: user, workspace: workspace, task: task} do
      [summary] =
        Tasks.list_task_summaries!(
          tenant: workspace.id,
          actor: user
        )

      assert summary.id == task.id
    end

    test "only exposes expected public attributes", _context do
      public_attrs =
        TaskSummary
        |> Info.public_attributes()
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert public_attrs == [:due_date, :human_id, :id, :priority, :title]
    end
  end
end
