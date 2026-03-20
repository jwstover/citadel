defmodule Citadel.Tasks.Changes.InheritRefinementCycleWorkspace do
  @moduledoc false
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, %{tenant: tenant}) do
    case Ash.Changeset.get_attribute(changeset, :refinement_cycle_id) do
      nil ->
        changeset

      refinement_cycle_id ->
        set_workspace_from_cycle(changeset, refinement_cycle_id, tenant)
    end
  end

  defp set_workspace_from_cycle(changeset, refinement_cycle_id, tenant) do
    case Citadel.Tasks.RefinementCycle
         |> Ash.Query.filter(id == ^refinement_cycle_id)
         |> Ash.read_one(authorize?: false, tenant: tenant) do
      {:ok, %{workspace_id: workspace_id}} ->
        Ash.Changeset.force_change_attribute(changeset, :workspace_id, workspace_id)

      {:ok, nil} ->
        Ash.Changeset.add_error(changeset,
          field: :refinement_cycle_id,
          message: "refinement cycle not found"
        )

      {:error, _} ->
        Ash.Changeset.add_error(changeset,
          field: :refinement_cycle_id,
          message: "refinement cycle not found"
        )
    end
  end
end
