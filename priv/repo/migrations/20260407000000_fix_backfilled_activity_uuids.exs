defmodule Citadel.Repo.Migrations.FixBackfilledActivityUuids do
  @moduledoc """
  Regenerates UUIDs for backfilled agent_run activities that were
  incorrectly created with gen_random_uuid() (v4) instead of
  uuid_generate_v7(). The v4 UUIDs fail to load as Ash.Type.UUIDv7.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE task_activities
    SET id = uuid_generate_v7()
    WHERE type = 'agent_run'
      AND agent_run_id IS NOT NULL
    """)
  end

  def down do
    :ok
  end
end
