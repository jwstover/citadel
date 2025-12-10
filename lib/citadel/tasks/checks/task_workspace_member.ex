defmodule Citadel.Tasks.Checks.TaskWorkspaceMember do
  @moduledoc """
  Policy check for TaskAssignment creates.

  Verifies the actor is a member of the workspace that the task belongs to.
  Used when creating join records where multitenancy isn't directly available.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts) do
    "actor is a member of the task's workspace"
  end

  @impl true
  def match?(actor, %{changeset: changeset} = context, _opts) when not is_nil(actor) do
    task_id = Ash.Changeset.get_attribute(changeset, :task_id)
    tenant = Map.get(context, :tenant) || changeset.tenant

    if is_nil(task_id) do
      false
    else
      workspace_member?(actor.id, task_id, tenant)
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp workspace_member?(actor_id, task_id, tenant) do
    require Ash.Query

    opts = [authorize?: false, load: [:workspace]]
    opts = if tenant, do: Keyword.put(opts, :tenant, tenant), else: opts

    case Ash.get(Citadel.Tasks.Task, task_id, opts) do
      {:ok, task} ->
        workspace = task.workspace

        workspace.owner_id == actor_id or
          Citadel.Accounts.WorkspaceMembership
          |> Ash.Query.filter(workspace_id == ^workspace.id and user_id == ^actor_id)
          |> Ash.exists?(authorize?: false)

      _ ->
        false
    end
  end
end
