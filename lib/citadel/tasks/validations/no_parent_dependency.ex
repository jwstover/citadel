defmodule Citadel.Tasks.Validations.NoParentDependency do
  @moduledoc """
  Validates that a task dependency does not point to the task's own parent.
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    task_id = Ash.Changeset.get_attribute(changeset, :task_id)
    depends_on_task_id = Ash.Changeset.get_attribute(changeset, :depends_on_task_id)

    if is_nil(task_id) or is_nil(depends_on_task_id) do
      :ok
    else
      require Ash.Query

      case Citadel.Tasks.Task
           |> Ash.Query.filter(id == ^task_id)
           |> Ash.Query.select([:parent_task_id])
           |> Ash.read_one(authorize?: false, tenant: changeset.tenant) do
        {:ok, %{parent_task_id: ^depends_on_task_id}} ->
          {:error, field: :depends_on_task_id, message: "a task cannot depend on its parent task"}

        _ ->
          :ok
      end
    end
  end
end
