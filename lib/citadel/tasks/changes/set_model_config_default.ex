defmodule Citadel.Tasks.Changes.SetModelConfigDefault do
  @moduledoc """
  Sets this model config as the workspace default and unsets all others.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      changeset = Ash.Changeset.force_change_attribute(changeset, :is_default, true)

      require Ash.Query

      Citadel.Tasks.ModelConfig
      |> Ash.Query.filter(is_default == true and id != ^changeset.data.id)
      |> Ash.Query.set_tenant(changeset.tenant)
      |> Ash.read!(authorize?: false)
      |> Enum.each(fn config ->
        config
        |> Ash.Changeset.for_update(:unset_default, %{},
          authorize?: false,
          tenant: changeset.tenant
        )
        |> Ash.update!()
      end)

      changeset
    end)
  end
end
