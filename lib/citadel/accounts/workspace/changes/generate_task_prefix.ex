defmodule Citadel.Accounts.Workspace.Changes.GenerateTaskPrefix do
  @moduledoc """
  Generates a task prefix from the workspace name.

  Algorithm:
  1. Extract uppercase letters from workspace name
  2. If 1-3 uppercase letters, use them (e.g., "My Project" → "MP")
  3. If >3, take first 3 (e.g., "SUPER LONG" → "SUP")
  4. If none, take first 1-3 letters uppercased (e.g., "acme" → "ACM")
  5. Fallback: "WS"
  """
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :task_prefix) do
      changeset
    else
      name = Ash.Changeset.get_attribute(changeset, :name)
      prefix = generate_prefix(name)
      Ash.Changeset.change_attribute(changeset, :task_prefix, prefix)
    end
  end

  defp generate_prefix(nil), do: "WS"
  defp generate_prefix(""), do: "WS"

  defp generate_prefix(name) do
    uppercase_letters = String.replace(name, ~r/[^A-Z]/, "")

    cond do
      String.length(uppercase_letters) >= 1 and String.length(uppercase_letters) <= 3 ->
        uppercase_letters

      String.length(uppercase_letters) > 3 ->
        String.slice(uppercase_letters, 0, 3)

      true ->
        name
        |> String.replace(~r/[^a-zA-Z]/, "")
        |> String.slice(0, 3)
        |> String.upcase()
        |> case do
          "" -> "WS"
          prefix -> prefix
        end
    end
  end
end
