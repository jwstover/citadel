defmodule Citadel.Repo.Migrations.BackfillAgentRunActivities do
  @moduledoc """
  Backfills TaskActivity records for all existing AgentRun records
  that don't already have a linked activity entry.

  This is idempotent — safe to run multiple times.
  """

  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO task_activities (id, type, actor_type, actor_display_name, task_id, workspace_id, agent_run_id, inserted_at, updated_at)
    SELECT uuid_generate_v7(), 'agent_run', 'ai', 'Agent', task_id, workspace_id, id, inserted_at, inserted_at
    FROM agent_runs
    WHERE NOT EXISTS (
      SELECT 1 FROM task_activities WHERE task_activities.agent_run_id = agent_runs.id
    )
    """)
  end

  def down do
    execute("""
    DELETE FROM task_activities
    WHERE type = 'agent_run'
      AND agent_run_id IS NOT NULL
      AND agent_run_id IN (SELECT id FROM agent_runs)
    """)
  end
end
