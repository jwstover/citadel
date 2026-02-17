defmodule Citadel.Repo.Migrations.AddBacklogStateAndColors do
  @moduledoc """
  Adds Backlog state, updates colors/icons for all states, and reorders states.
  """

  use Ecto.Migration

  def up do
    # Add unique constraint on name for upserts (drop first to be idempotent)
    drop_if_exists unique_index(:task_states, [:name])
    create unique_index(:task_states, [:name])

    # Upsert In Progress state
    execute """
    INSERT INTO task_states (id, name, icon, foreground_color, background_color, "order", is_complete, inserted_at, updated_at)
    VALUES (
      uuid_generate_v7(),
      'In Progress',
      'fa-circle-half-stroke-solid',
      '#ffffff',
      '#eab308',
      1,
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

    # Upsert Todo state
    execute """
    INSERT INTO task_states (id, name, icon, foreground_color, background_color, "order", is_complete, inserted_at, updated_at)
    VALUES (
      uuid_generate_v7(),
      'Todo',
      'fa-circle-regular',
      '#ffffff',
      '#0284c7',
      2,
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

    # Upsert Backlog state
    execute """
    INSERT INTO task_states (id, name, icon, foreground_color, background_color, "order", is_complete, inserted_at, updated_at)
    VALUES (
      uuid_generate_v7(),
      'Backlog',
      'fa-circle-regular',
      '#ffffff',
      '#6b7280',
      3,
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

    # Upsert Complete state
    execute """
    INSERT INTO task_states (id, name, icon, foreground_color, background_color, "order", is_complete, inserted_at, updated_at)
    VALUES (
      uuid_generate_v7(),
      'Complete',
      'fa-circle-solid',
      '#ffffff',
      '#16a34a',
      4,
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
    # Delete Backlog state
    execute """
    DELETE FROM task_states WHERE name = 'Backlog'
    """

    # Restore original order and clear icons/colors
    execute """
    UPDATE task_states SET
      icon = NULL,
      foreground_color = NULL,
      background_color = NULL,
      "order" = 1
    WHERE name = 'Todo'
    """

    execute """
    UPDATE task_states SET
      icon = NULL,
      foreground_color = NULL,
      background_color = NULL,
      "order" = 2
    WHERE name = 'In Progress'
    """

    execute """
    UPDATE task_states SET
      icon = NULL,
      foreground_color = NULL,
      background_color = NULL,
      "order" = 3,
      is_complete = false
    WHERE name = 'Complete'
    """

    drop_if_exists unique_index(:task_states, [:name])
  end
end
