defmodule Citadel.Tasks.Changes.SetDefaultTaskState do
  @moduledoc """
  Sets the default task_state_id to the TaskState with the lowest order
  if no task_state_id is provided.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    # Only set default if task_state_id is not already provided
    if Ash.Changeset.get_argument(changeset, :task_state_id) ||
         Ash.Changeset.changing_attribute?(changeset, :task_state_id) do
      changeset
    else
      set_default_state(changeset)
    end
  end

  defp set_default_state(changeset) do
    require Ash.Query

    case Citadel.Tasks.TaskState
         |> Ash.Query.sort(order: :asc)
         |> Ash.Query.limit(1)
         |> Ash.read() do
      {:ok, [state | _]} ->
        Ash.Changeset.change_attribute(changeset, :task_state_id, state.id)

      {:ok, []} ->
        Ash.Changeset.add_error(changeset, "No task states available")

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end
end
