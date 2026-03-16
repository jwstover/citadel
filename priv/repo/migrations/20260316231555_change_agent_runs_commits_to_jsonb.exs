defmodule Citadel.Repo.Migrations.ChangeAgentRunsCommitsToJsonb do
  use Ecto.Migration

  def up do
    alter table(:agent_runs) do
      remove :commits
      add :commits, {:array, :map}, default: []
    end
  end

  def down do
    alter table(:agent_runs) do
      remove :commits
      add :commits, {:array, :text}, default: []
    end
  end
end
