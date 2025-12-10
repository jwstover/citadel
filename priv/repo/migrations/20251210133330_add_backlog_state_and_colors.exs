defmodule Citadel.Repo.Migrations.AddBacklogStateAndColors do
  @moduledoc """
  Adds Backlog state, updates colors/icons for all states, and reorders states.
  """

  use Ecto.Migration

  def up do
    # Update existing states with icons, colors, and new order
    execute """
    UPDATE task_states SET
      icon = 'fa-circle-half-stroke-solid',
      foreground_color = '#ffffff',
      background_color = '#eab308',
      "order" = 1
    WHERE name = 'In Progress'
    """

    execute """
    UPDATE task_states SET
      icon = 'fa-circle-regular',
      foreground_color = '#ffffff',
      background_color = '#0284c7',
      "order" = 2
    WHERE name = 'Todo'
    """

    execute """
    UPDATE task_states SET
      icon = 'fa-circle-solid',
      foreground_color = '#ffffff',
      background_color = '#16a34a',
      "order" = 4,
      is_complete = true
    WHERE name = 'Complete'
    """

    # Insert new Backlog state
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
  end
end
