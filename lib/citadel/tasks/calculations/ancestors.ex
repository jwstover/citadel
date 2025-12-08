defmodule Citadel.Tasks.Calculations.Ancestors do
  @moduledoc """
  Calculates the ancestor chain for a task using a recursive CTE.
  Returns ancestors ordered from root to immediate parent.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:parent_task_id]
  end

  @impl true
  def calculate(records, _opts, _context) do
    task_ids = Enum.map(records, & &1.id)

    ancestors_by_task_id =
      task_ids
      |> fetch_ancestors()
      |> Enum.group_by(& &1.descendant_id)

    Enum.map(records, fn record ->
      ancestors_by_task_id
      |> Map.get(record.id, [])
      |> Enum.sort_by(& &1.depth, :desc)
      |> Enum.map(&Map.take(&1, [:id, :human_id, :title]))
    end)
  end

  defp fetch_ancestors([]), do: []

  # sobelow_skip ["SQL.Query"]
  defp fetch_ancestors(task_ids) do
    # Convert UUIDs to raw binary format for Postgrex
    binary_ids = Enum.map(task_ids, fn id -> Ecto.UUID.dump!(to_string(id)) end)

    placeholders =
      binary_ids
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {_, i} -> "$#{i}" end)

    query = """
    WITH RECURSIVE ancestors AS (
      SELECT
        t.id,
        t.human_id,
        t.title,
        t.parent_task_id,
        t.id as descendant_id,
        0 as depth
      FROM tasks t
      WHERE t.id IN (#{placeholders})

      UNION ALL

      SELECT
        parent.id,
        parent.human_id,
        parent.title,
        parent.parent_task_id,
        ancestors.descendant_id,
        ancestors.depth + 1
      FROM tasks parent
      INNER JOIN ancestors ON ancestors.parent_task_id = parent.id
    )
    SELECT id, human_id, title, descendant_id, depth
    FROM ancestors
    WHERE depth > 0
    ORDER BY descendant_id, depth DESC
    """

    case Citadel.Repo.query(query, binary_ids) do
      {:ok, %{rows: rows, columns: columns}} ->
        columns = Enum.map(columns, &safe_to_atom/1)

        Enum.map(rows, fn row ->
          row
          |> Enum.zip(columns)
          |> Enum.map(&convert_uuid_fields/1)
          |> Map.new()
        end)

      {:error, _} ->
        []
    end
  end

  defp convert_uuid_fields({value, key}) when key in [:id, :descendant_id] and is_binary(value) do
    {:ok, uuid_string} = Ecto.UUID.load(value)
    {key, uuid_string}
  end

  defp convert_uuid_fields({value, key}), do: {key, value}

  @allowed_columns ~w(id human_id title descendant_id depth)
  defp safe_to_atom(column) when column in @allowed_columns do
    String.to_existing_atom(column)
  end
end
