defmodule Citadel.Repo.Migrations.AddCancelledTaskState do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO task_states (id, name, icon, foreground_color, background_color, "order", is_complete, inserted_at, updated_at)
    VALUES (
      uuid_generate_v7(),
      'Cancelled',
      'fa-ban-solid',
      '#ffffff',
      '#6b7280',
      6,
      true,
      NOW(),
      NOW()
    )
    ON CONFLICT (name) DO UPDATE SET
      icon = EXCLUDED.icon,
      foreground_color = EXCLUDED.foreground_color,
      background_color = EXCLUDED.background_color,
      "order" = EXCLUDED."order",
      is_complete = EXCLUDED.is_complete,
      updated_at = NOW()
    """
  end

  def down do
    execute "DELETE FROM task_states WHERE name = 'Cancelled'"
  end
end
