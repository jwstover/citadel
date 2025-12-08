defmodule Citadel.Tasks.Changes.AssignHumanId do
  @moduledoc """
  Assigns a human-readable ID to a task in the format PREFIX-NUMBER.
  The prefix comes from the workspace's task_prefix, and the number
  is atomically incremented from the workspace's task counter.
  """
  use Ash.Resource.Change

  require Ash.Query

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)

      case get_human_id(workspace_id) do
        {:ok, human_id} ->
          Ash.Changeset.force_change_attribute(changeset, :human_id, human_id)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp get_human_id(workspace_id) do
    with {:ok, prefix} <- get_workspace_prefix(workspace_id),
         {:ok, number} <- increment_counter(workspace_id) do
      {:ok, "#{prefix}-#{number}"}
    end
  end

  defp get_workspace_prefix(workspace_id) do
    case Citadel.Accounts.Workspace
         |> Ash.Query.filter(id == ^workspace_id)
         |> Ash.Query.select([:task_prefix])
         |> Ash.read_one(authorize?: false) do
      {:ok, %{task_prefix: prefix}} -> {:ok, prefix}
      {:ok, nil} -> {:error, "Workspace not found"}
      {:error, error} -> {:error, error}
    end
  end

  defp increment_counter(workspace_id) do
    case Citadel.Tasks.get_task_counter(workspace_id, authorize?: false) do
      {:ok, counter} ->
        case Citadel.Tasks.increment_task_counter(counter, authorize?: false) do
          {:ok, updated_counter} -> {:ok, updated_counter.last_task_number}
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end
end
