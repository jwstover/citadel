defmodule Citadel.Tasks.TaskDependency do
  @moduledoc """
  Join resource linking tasks to their dependencies.
  Enables task dependencies where one task must be completed before another can start.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "task_dependencies"
    repo Citadel.Repo

    references do
      reference :task, index?: true, on_delete: :delete
      reference :depends_on_task, index?: true, on_delete: :delete
    end

    check_constraints do
      check_constraint :task_id,
        name: "no_self_reference",
        check: "task_id != depends_on_task_id",
        message: "a task cannot depend on itself"
    end
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :update do
      primary? true
      require_atomic? false
      accept :*
    end

    read :list_dependencies do
      argument :task_id, :uuid, allow_nil?: false
      filter expr(task_id == ^arg(:task_id))
    end

    read :list_dependents do
      argument :task_id, :uuid, allow_nil?: false
      filter expr(depends_on_task_id == ^arg(:task_id))
    end

    create :add_by_human_id do
      argument :task_id, :uuid, allow_nil?: false
      argument :depends_on_human_id, :string, allow_nil?: false

      change fn changeset, _context ->
        require Ash.Query

        task_id = Ash.Changeset.get_argument(changeset, :task_id)
        human_id = Ash.Changeset.get_argument(changeset, :depends_on_human_id)
        tenant = changeset.tenant

        case Citadel.Tasks.Task
             |> Ash.Query.filter(human_id == ^human_id)
             |> Ash.Query.select([:id, :workspace_id])
             |> Ash.read_one(
               authorize?: false,
               tenant: tenant
             ) do
          {:ok, nil} ->
            Ash.Changeset.add_error(
              changeset,
              field: :depends_on_human_id,
              message: "task not found"
            )

          {:ok, depends_on_task} ->
            changeset
            |> Ash.Changeset.change_attribute(:task_id, task_id)
            |> Ash.Changeset.change_attribute(:depends_on_task_id, depends_on_task.id)

          {:error, error} ->
            Ash.Changeset.add_error(changeset, error)
        end
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     task.workspace.owner_id == ^actor(:id) or
                       exists(task.workspace.memberships, user_id == ^actor(:id))
                   )
    end

    policy action_type(:create) do
      authorize_if Citadel.Tasks.Checks.TaskWorkspaceMember
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(
                     task.workspace.owner_id == ^actor(:id) or
                       exists(task.workspace.memberships, user_id == ^actor(:id))
                   )
    end
  end

  pub_sub do
    module CitadelWeb.Endpoint
    prefix "tasks"

    publish_all :create, ["task_dependencies", :task_id] do
      transform fn %{data: dep} ->
        %{
          task_id: dep.task_id,
          depends_on_task_id: dep.depends_on_task_id,
          action: :create
        }
      end
    end

    publish_all :create, ["task_dependents", :depends_on_task_id] do
      transform fn %{data: dep} ->
        %{
          task_id: dep.task_id,
          depends_on_task_id: dep.depends_on_task_id,
          action: :create
        }
      end
    end

    publish_all :destroy, ["task_dependencies", :task_id] do
      transform fn %{data: dep} ->
        %{
          task_id: dep.task_id,
          depends_on_task_id: dep.depends_on_task_id,
          action: :destroy
        }
      end
    end

    publish_all :destroy, ["task_dependents", :depends_on_task_id] do
      transform fn %{data: dep} ->
        %{
          task_id: dep.task_id,
          depends_on_task_id: dep.depends_on_task_id,
          action: :destroy
        }
      end
    end
  end

  validations do
    validate Citadel.Tasks.Validations.NoCircularDependency
  end

  attributes do
    uuid_v7_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :task, Citadel.Tasks.Task, allow_nil?: false, public?: true
    belongs_to :depends_on_task, Citadel.Tasks.Task, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_dependency, [:task_id, :depends_on_task_id]
  end
end
