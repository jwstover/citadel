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

  alias Ash.Error.Query.NotFound
  alias Citadel.AI.Helpers

  # AI model access is now abstracted through Citadel.AI.Helpers

  postgres do
    table "tasks"
    repo Citadel.Repo

    references do
      reference :parent_task, index?: true, on_delete: :delete
      reference :project, index?: true, on_delete: :nilify
      reference :model_config, index?: true, on_delete: :nilify
      reference :active_agent_run, index?: true, on_delete: :nilify
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
        :project_id,
        :due_date,
        :priority,
        :agent_eligible,
        :model_config_id,
        :refinement_config
      ]

      argument :assignees, {:array, :uuid}
      argument :dependencies, {:array, :uuid}

      change relate_actor(:user)
      change Citadel.Tasks.Changes.InheritParentWorkspace
      change Citadel.Tasks.Changes.AssignHumanId
      change Citadel.Tasks.Changes.SetDefaultTaskState
      change manage_relationship(:assignees, type: :append_and_remove, on_lookup: :relate)
      change manage_relationship(:dependencies, type: :append_and_remove, on_lookup: :relate)

      validate Citadel.Tasks.Validations.NoCircularParent
      validate Citadel.Tasks.Validations.AssigneesWorkspaceMembers

      change Citadel.Tasks.Changes.MaybeEnqueueAgentWork
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :title,
        :description,
        :task_state_id,
        :due_date,
        :priority,
        :parent_task_id,
        :project_id,
        :active_agent_run_id,
        :agent_eligible,
        :forge_pr,
        :model_config_id,
        :refinement_config
      ]

      argument :assignees, {:array, :uuid}

      change manage_relationship(:assignees, type: :append_and_remove, on_lookup: :relate)

      validate Citadel.Tasks.Validations.AssigneesWorkspaceMembers
      validate Citadel.Tasks.Validations.NoCircularParent

      change Citadel.Tasks.Changes.MaybeEnqueueAgentWork
      change Citadel.Tasks.Changes.MaybeCancelPendingWorkItems
    end

    action :get_task_details, :string do
      description "Gets full details for a specific task by its human-readable ID (e.g. P-42). Returns a formatted string with title, state, priority, description, assignees, dependencies, sub-tasks, and parent task."

      argument :human_id, :string do
        allow_nil? false
        description "The human-readable task ID (e.g. P-42)"
      end

      run fn input, context ->
        human_id = input.arguments.human_id
        actor = context.actor
        tenant = context.tenant

        require Ash.Query

        task =
          Citadel.Tasks.Task
          |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: tenant)
          |> Ash.Query.filter(human_id == ^human_id)
          |> Ash.read_one!(
            load: [
              :task_state,
              :assignees,
              :parent_task,
              sub_tasks: [:task_state],
              dependencies: [:task_state]
            ]
          )

        case task do
          nil ->
            {:error,
             NotFound.exception(
               resource: Citadel.Tasks.Task,
               primary_key: %{human_id: human_id}
             )}

          task ->
            {:ok, format_task(task)}
        end
      end
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

    policy action_type(:action) do
      authorize_if always()
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
          workspace_id: task.workspace_id,
          agent_eligible: task.agent_eligible,
          forge_pr: task.forge_pr
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
          workspace_id: task.workspace_id,
          agent_eligible: task.agent_eligible,
          forge_pr: task.forge_pr
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
          workspace_id: task.workspace_id,
          agent_eligible: task.agent_eligible,
          forge_pr: task.forge_pr
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
          workspace_id: task.workspace_id,
          agent_eligible: task.agent_eligible,
          forge_pr: task.forge_pr
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
          workspace_id: task.workspace_id,
          agent_eligible: task.agent_eligible,
          forge_pr: task.forge_pr
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

    attribute :agent_eligible, :boolean do
      public? true
      default false
    end

    attribute :forge_pr, :string, public?: true

    attribute :refinement_config, :map, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace, public?: true, allow_nil?: false
    belongs_to :task_state, Citadel.Tasks.TaskState, public?: true, allow_nil?: false
    belongs_to :user, Citadel.Accounts.User, allow_nil?: false
    belongs_to :project, Citadel.Projects.Project, public?: true, allow_nil?: true
    belongs_to :active_agent_run, Citadel.Tasks.AgentRun, public?: true, allow_nil?: true
    belongs_to :model_config, Citadel.Tasks.ModelConfig, public?: true, allow_nil?: true
    belongs_to :parent_task, __MODULE__, public?: true, allow_nil?: true
    has_many :sub_tasks, __MODULE__, destination_attribute: :parent_task_id
    has_many :agent_runs, Citadel.Tasks.AgentRun
    has_many :work_items, Citadel.Tasks.AgentWorkItem

    many_to_many :assignees, Citadel.Accounts.User do
      through Citadel.Tasks.TaskAssignment
      source_attribute_on_join_resource :task_id
      destination_attribute_on_join_resource :assignee_id
      public? true
    end

    many_to_many :dependencies, __MODULE__ do
      through Citadel.Tasks.TaskDependency
      source_attribute_on_join_resource :task_id
      destination_attribute_on_join_resource :depends_on_task_id
      public? true
    end

    many_to_many :dependents, __MODULE__ do
      through Citadel.Tasks.TaskDependency
      source_attribute_on_join_resource :depends_on_task_id
      destination_attribute_on_join_resource :task_id
      public? true
    end

    has_many :activities, Citadel.Tasks.TaskActivity
  end

  calculations do
    calculate :ancestors, {:array, :map}, Citadel.Tasks.Calculations.Ancestors
    calculate :overdue?, :boolean, expr(not is_nil(due_date) and due_date < today())
    calculate :days_until_due, :integer, Citadel.Tasks.Calculations.DaysUntilDue
    calculate :blocked?, :boolean, Citadel.Tasks.Calculations.Blocked
    calculate :blocking_count, :integer, Citadel.Tasks.Calculations.BlockingCount

    calculate :execution_status, :atom, Citadel.Tasks.Calculations.ExecutionStatus do
      constraints one_of: [:none, :pending, :running, :completed, :failed, :cancelled]
    end
  end

  identities do
    identity :unique_human_id, [:workspace_id, :human_id]
  end

  defp format_task(task) do
    sections = [
      "# #{task.human_id}: #{task.title}",
      "State: #{task.task_state.name} | Priority: #{task.priority} | Due: #{task.due_date || "None"}",
      format_description(task.description),
      format_parent(task.parent_task),
      format_assignees(task.assignees),
      format_dependencies(task.dependencies),
      format_sub_tasks(task.sub_tasks)
    ]

    sections
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_description(nil), do: nil
  defp format_description(""), do: nil
  defp format_description(desc), do: "\n## Description\n#{desc}"

  defp format_parent(nil), do: nil
  defp format_parent(%Ash.NotLoaded{}), do: nil
  defp format_parent(parent), do: "\nParent: #{parent.human_id} - #{parent.title}"

  defp format_assignees([]), do: nil
  defp format_assignees(%Ash.NotLoaded{}), do: nil

  defp format_assignees(assignees) do
    list = Enum.map_join(assignees, ", ", fn user -> user.name || to_string(user.email) end)
    "\nAssignees: #{list}"
  end

  defp format_dependencies([]), do: nil
  defp format_dependencies(%Ash.NotLoaded{}), do: nil

  defp format_dependencies(deps) do
    list = Enum.map_join(deps, "\n", &"  - #{&1.human_id}: #{&1.title} [#{&1.task_state.name}]")
    "\n## Dependencies\n#{list}"
  end

  defp format_sub_tasks([]), do: nil
  defp format_sub_tasks(%Ash.NotLoaded{}), do: nil

  defp format_sub_tasks(sub_tasks) do
    list =
      Enum.map_join(sub_tasks, "\n", &"  - #{&1.human_id}: #{&1.title} [#{&1.task_state.name}]")

    "\n## Sub-tasks\n#{list}"
  end
end
