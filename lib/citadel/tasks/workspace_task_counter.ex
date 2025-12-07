defmodule Citadel.Tasks.WorkspaceTaskCounter do
  @moduledoc """
  Tracks the last assigned task number for each workspace.
  Used for generating sequential human-readable task IDs.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Tasks,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "workspace_task_counters"
    repo Citadel.Repo

    references do
      reference :workspace, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:workspace_id]
    end

    update :increment do
      change atomic_update(:last_task_number, expr(last_task_number + 1))
    end
  end

  attributes do
    attribute :workspace_id, :uuid do
      primary_key? true
      allow_nil? false
      public? true
    end

    attribute :last_task_number, :integer do
      allow_nil? false
      default 0
      public? true
    end
  end

  relationships do
    belongs_to :workspace, Citadel.Accounts.Workspace do
      define_attribute? false
      allow_nil? false
    end
  end
end
