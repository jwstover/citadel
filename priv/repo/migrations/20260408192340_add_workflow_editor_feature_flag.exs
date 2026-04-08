defmodule Citadel.Repo.Migrations.AddWorkflowEditorFeatureFlag do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO feature_flags (id, key, enabled, description, inserted_at, updated_at)
    VALUES (
      uuid_generate_v7(),
      'workflow_editor',
      true,
      'Prototype workflow editor UI',
      (now() AT TIME ZONE 'utc'),
      (now() AT TIME ZONE 'utc')
    )
    ON CONFLICT (key) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM feature_flags WHERE key = 'workflow_editor'"
  end
end
