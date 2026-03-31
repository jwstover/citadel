defmodule Citadel.Tasks.Changes.CreateQuestionAnswer do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, activity ->
      create_work_item(activity)
      {:ok, activity}
    end)
  end

  defp create_work_item(activity) do
    session_id = get_session_id(activity)

    Citadel.Tasks.AgentWorkItem
    |> Ash.Changeset.for_create(
      :create,
      %{
        type: :question_answered,
        task_id: activity.task_id,
        comment_id: activity.id,
        session_id: session_id
      },
      authorize?: false,
      tenant: activity.workspace_id
    )
    |> Ash.create()
    |> case do
      {:ok, _work_item} -> :ok
      {:error, _} -> :ok
    end
  end

  defp get_session_id(%{parent_activity_id: nil}), do: nil

  defp get_session_id(activity) do
    case get_parent_activity(activity) do
      {:ok, %{agent_run: %{session_id: session_id}}} -> session_id
      _ -> nil
    end
  end

  defp get_parent_activity(activity) do
    Citadel.Tasks.TaskActivity
    |> Ash.Query.filter(id == ^activity.parent_activity_id)
    |> Ash.Query.load([:agent_run])
    |> Ash.read_one(authorize?: false, tenant: activity.workspace_id)
  end
end
