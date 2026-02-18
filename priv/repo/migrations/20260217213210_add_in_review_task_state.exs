defmodule Citadel.Repo.Migrations.AddInReviewTaskState do
  use Ecto.Migration

  def up do
    execute "UPDATE task_states SET \"order\" = 5 WHERE name = 'Complete'"

    execute """
    INSERT INTO task_states (id, name, icon, foreground_color, background_color, "order", is_complete, inserted_at, updated_at)
    VALUES (
      uuid_generate_v7(),
      'In Review',
      'fa-circle-dot-solid',
      '#ffffff',
      '#9333ea',
      4,
      false,
      NOW(),
      NOW()
    )
    ON CONFLICT (name) DO UPDATE SET
      icon = EXCLUDED.icon,
      foreground_color = EXCLUDED.foreground_color,
      background_color = EXCLUDED.background_color,
      "order" = EXCLUDED."order",
      updated_at = NOW()
    """
  end

  def down do
    execute "DELETE FROM task_states WHERE name = 'In Review'"
    execute "UPDATE task_states SET \"order\" = 4 WHERE name = 'Complete'"
  end
end
