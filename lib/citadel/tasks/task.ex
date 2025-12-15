defmodule Citadel.Tasks.Task do
  @moduledoc """
  Represents a task item with a title, description, and associated state.
  Tasks are workspace-scoped and can be accessed by all members of the workspace.
  The user relationship tracks who originally created the task.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAi],
    notifiers: [Ash.Notifier.PubSub]

  alias Citadel.AI.Helpers

  # AI model access is now abstracted through Citadel.AI.Helpers

  postgres do
    table "tasks"
    repo Citadel.Repo

    references do
      reference :parent_task, index?: true, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    read :list_sub_tasks do
      argument :parent_task_id, :uuid, allow_nil?: false
      filter expr(parent_task_id == ^arg(:parent_task_id))
    end

    read :list_top_level do
      filter expr(is_nil(parent_task_id))
    end

    create :create do
      accept [
        :title,
        :description,
        :task_state_id,
        :workspace_id,
        :parent_task_id,
        :due_date,
        :priority
      ]

      argument :assignees, {:array, :uuid}

      change relate_actor(:user)
      change Citadel.Tasks.Changes.InheritParentWorkspace
      change Citadel.Tasks.Changes.AssignHumanId
      change Citadel.Tasks.Changes.SetDefaultTaskState
      change manage_relationship(:assignees, type: :append_and_remove, on_lookup: :relate)

      validate Citadel.Tasks.Validations.NoCircularParent
      validate Citadel.Tasks.Validations.AssigneesWorkspaceMembers
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:title, :description, :task_state_id, :due_date, :priority]

      argument :assignees, {:array, :uuid}

      change manage_relationship(:assignees, type: :append_and_remove, on_lookup: :relate)

      validate Citadel.Tasks.Validations.AssigneesWorkspaceMembers
    end

    action :parse_task_from_text, :map do
      description """
      Parses natural language text into task attributes.
      Extract a concise title (max 100 chars), optional description, and suggested state.
      The suggested_state should be one of: to_do, in_progress, or done.
      """

      argument :text, :string do
        allow_nil? false
        description "Natural language text describing the task to create"
      end

      run fn _input, _context ->
        model = Helpers.get_model()
        prompt(model)
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     workspace.owner_id == ^actor(:id) or
                       exists(workspace.memberships, user_id == ^actor(:id))
                   )
    end

    policy action_type(:create) do
      authorize_if Citadel.Accounts.Checks.TenantWorkspaceMember
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(
                     workspace.owner_id == ^actor(:id) or
                       exists(workspace.memberships, user_id == ^actor(:id))
                   )
    end
  end

  pub_sub do
    module CitadelWeb.Endpoint
    prefix "tasks"

    publish_all :create, ["tasks", :workspace_id] do
      transform fn %{data: task} ->
        %{
          id: task.id,
          human_id: task.human_id,
          title: task.title,
          description: task.description,
          task_state_id: task.task_state_id,
          priority: task.priority,
          due_date: task.due_date,
          parent_task_id: task.parent_task_id,
          workspace_id: task.workspace_id
        }
      end
    end

    publish_all :update, ["tasks", :workspace_id] do
      transform fn %{data: task} ->
        %{
          id: task.id,
          human_id: task.human_id,
          title: task.title,
          description: task.description,
          task_state_id: task.task_state_id,
          priority: task.priority,
          due_date: task.due_date,
          parent_task_id: task.parent_task_id,
          workspace_id: task.workspace_id
        }
      end
    end

    publish_all :destroy, ["tasks", :workspace_id] do
      transform fn %{data: task} ->
        %{id: task.id, task_state_id: task.task_state_id, action: :destroy}
      end
    end

    publish :update, ["task", :id] do
      transform fn %{data: task} ->
        %{
          id: task.id,
          human_id: task.human_id,
          title: task.title,
          description: task.description,
          task_state_id: task.task_state_id,
          priority: task.priority,
          due_date: task.due_date,
          parent_task_id: task.parent_task_id,
          workspace_id: task.workspace_id
        }
      end
    end

    publish :create, ["task_children", :parent_task_id] do
      transform fn %{data: task} ->
        %{
          id: task.id,
          human_id: task.human_id,
          title: task.title,
          description: task.description,
          task_state_id: task.task_state_id,
          priority: task.priority,
          due_date: task.due_date,
          parent_task_id: task.parent_task_id,
          workspace_id: task.workspace_id
        }
      end
    end

    publish :update, ["task_children", :parent_task_id] do
      transform fn %{data: task} ->
        %{
          id: task.id,
          human_id: task.human_id,
          title: task.title,
          description: task.description,
          task_state_id: task.task_state_id,
          priority: task.priority,
          due_date: task.due_date,
          parent_task_id: task.parent_task_id,
          workspace_id: task.workspace_id
        }
      end
    end

    publish :destroy, ["task_children", :parent_task_id] do
      transform fn %{data: task} ->
        %{id: task.id, task_state_id: task.task_state_id, action: :destroy}
      end
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :human_id, :string do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :title, :string, public?: true, allow_nil?: false
    attribute :description, :string, public?: true
    attribute :due_date, :date, public?: true

    attribute :priority, Citadel.Tasks.Task.Types.Priority do
      public? true
      default :medium
    end

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
    belongs_to :task_state, Citadel.Tasks.TaskState, public?: true, allow_nil?: false
    belongs_to :user, Citadel.Accounts.User, allow_nil?: false
    belongs_to :parent_task, __MODULE__, public?: true, allow_nil?: true
    has_many :sub_tasks, __MODULE__, destination_attribute: :parent_task_id

    many_to_many :assignees, Citadel.Accounts.User do
      through Citadel.Tasks.TaskAssignment
      source_attribute_on_join_resource :task_id
      destination_attribute_on_join_resource :assignee_id
      public? true
    end
  end

  calculations do
    calculate :ancestors, {:array, :map}, Citadel.Tasks.Calculations.Ancestors
    calculate :overdue?, :boolean, expr(not is_nil(due_date) and due_date < today())
    calculate :days_until_due, :integer, Citadel.Tasks.Calculations.DaysUntilDue
  end

  identities do
    identity :unique_human_id, [:workspace_id, :human_id]
  end
end
