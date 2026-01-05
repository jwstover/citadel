defmodule Citadel.Tasks.Validations.NoCircularDependency do
  @moduledoc """
  Validates that creating a task dependency does not create a circular reference.

  This prevents:
  1. A task from depending on itself
  2. A task from depending on a task that eventually depends back on it
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    task_id = Ash.Changeset.get_attribute(changeset, :task_id)
    depends_on_task_id = Ash.Changeset.get_attribute(changeset, :depends_on_task_id)

    validate_no_circular_dependency(task_id, depends_on_task_id)
  end

  defp validate_no_circular_dependency(task_id, depends_on_task_id) do
    cond do
      task_id == depends_on_task_id ->
        {:error,
         field: :depends_on_task_id, message: "a task cannot depend on itself"}

      creates_cycle?(task_id, depends_on_task_id) ->
        {:error,
         field: :depends_on_task_id, message: "would create a circular dependency"}

      true ->
        :ok
    end
  end

  defp creates_cycle?(_task_id, nil), do: false

  defp creates_cycle?(task_id, depends_on_task_id) do
    check_dependency_chain(task_id, depends_on_task_id, MapSet.new())
  end

  defp check_dependency_chain(task_id, current_dependency_id, visited) do
    cond do
      is_nil(current_dependency_id) ->
        false

      current_dependency_id == task_id ->
        true

      MapSet.member?(visited, current_dependency_id) ->
        false

      true ->
        get_dependency_ids(current_dependency_id)
        |> Enum.any?(fn next_dependency_id ->
          check_dependency_chain(
            task_id,
            next_dependency_id,
            MapSet.put(visited, current_dependency_id)
          )
        end)
    end
  end

  defp get_dependency_ids(task_id) do
    require Ash.Query

    case Citadel.Tasks.TaskDependency
         |> Ash.Query.filter(task_id == ^task_id)
         |> Ash.Query.select([:depends_on_task_id])
         |> Ash.read(authorize?: false) do
      {:ok, dependencies} -> Enum.map(dependencies, & &1.depends_on_task_id)
      _ -> []
    end
  end
end
