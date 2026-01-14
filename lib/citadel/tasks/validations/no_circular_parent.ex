defmodule Citadel.Tasks.Validations.NoCircularParent do
  @moduledoc """
  Validates that a task's parent_task_id does not create a circular reference.

  This prevents:
  1. A task from being its own parent
  2. A task from having a parent that eventually points back to itself
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:not_atomic, "Circular parent validation requires database queries to check ancestor chain"}
  end

  @impl true
  def validate(changeset, _opts, context) do
    tenant = context.tenant

    case Ash.Changeset.get_attribute(changeset, :parent_task_id) do
      nil ->
        :ok

      parent_task_id ->
        task_id = Ash.Changeset.get_attribute(changeset, :id)
        validate_no_circular_reference(task_id, parent_task_id, tenant)
    end
  end

  defp validate_no_circular_reference(task_id, parent_task_id, tenant) do
    cond do
      task_id == parent_task_id ->
        {:error, field: :parent_task_id, message: "a task cannot be its own parent"}

      creates_cycle?(task_id, parent_task_id, tenant) ->
        {:error, field: :parent_task_id, message: "would create a circular reference"}

      true ->
        :ok
    end
  end

  defp creates_cycle?(nil, _parent_task_id, _tenant), do: false

  defp creates_cycle?(task_id, parent_task_id, tenant) do
    check_ancestor_chain(task_id, parent_task_id, MapSet.new(), tenant)
  end

  defp check_ancestor_chain(task_id, current_parent_id, visited, tenant) do
    cond do
      is_nil(current_parent_id) ->
        false

      current_parent_id == task_id ->
        true

      MapSet.member?(visited, current_parent_id) ->
        true

      true ->
        case get_parent_task_id(current_parent_id, tenant) do
          nil ->
            false

          next_parent_id ->
            check_ancestor_chain(
              task_id,
              next_parent_id,
              MapSet.put(visited, current_parent_id),
              tenant
            )
        end
    end
  end

  defp get_parent_task_id(task_id, tenant) do
    require Ash.Query

    case Citadel.Tasks.Task
         |> Ash.Query.filter(id == ^task_id)
         |> Ash.Query.select([:parent_task_id])
         |> Ash.read_one(authorize?: false, tenant: tenant) do
      {:ok, %{parent_task_id: parent_id}} -> parent_id
      _ -> nil
    end
  end
end
