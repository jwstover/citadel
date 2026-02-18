defmodule Citadel.Accounts.Workspace do
  @moduledoc """
  A workspace groups users together to collaborate on tasks and conversations.
  Each workspace has an owner who can manage the workspace and invite other users.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspaces"
    repo Citadel.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :current do
      get? true
      filter expr(id == ^tenant())
      prepare build(select: [:id])
    end

    create :create do
      accept [:name, :organization_id]

      change relate_actor(:owner)
      change Citadel.Accounts.Workspace.Changes.GenerateTaskPrefix

      change fn changeset, context ->
        Ash.Changeset.after_action(changeset, fn _changeset, workspace ->
          # Automatically create membership for the owner
          Citadel.Accounts.add_workspace_member!(
            workspace.owner_id,
            workspace.id,
            actor: context.actor
          )

          # Initialize the task counter for this workspace
          Citadel.Tasks.create_workspace_task_counter!(%{workspace_id: workspace.id},
            authorize?: false
          )

          {:ok, workspace}
        end)
      end
    end

    update :update do
      accept [:name]
    end
  end

  policies do
    # Any authenticated user can create a workspace if within workspace limit
    policy action_type(:create) do
      forbid_unless Citadel.Billing.Checks.WithinWorkspaceLimit
      authorize_if actor_present()
    end

    # Owner and members can read the workspace
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
      authorize_if Citadel.Accounts.Checks.WorkspaceMember
    end

    # Only the owner can update the workspace
    policy action_type(:update) do
      authorize_if relates_to_actor_via(:owner)
    end

    # Only the owner can destroy the workspace
    policy action_type(:destroy) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true

      constraints min_length: 1,
                  max_length: 100,
                  trim?: true
    end

    attribute :task_prefix, :string do
      allow_nil? false
      public? true

      constraints min_length: 1,
                  max_length: 3,
                  match: ~r/^[A-Z]+$/
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Citadel.Accounts.Organization do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :owner, Citadel.Accounts.User do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    has_many :memberships, Citadel.Accounts.WorkspaceMembership do
      public? true
    end

    many_to_many :members, Citadel.Accounts.User do
      through Citadel.Accounts.WorkspaceMembership
      source_attribute_on_join_resource :workspace_id
      destination_attribute_on_join_resource :user_id
      public? true
    end
  end
end
