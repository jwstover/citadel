defmodule Citadel.Accounts.Organization.Changes.GenerateSlug do
  @moduledoc """
  Generates a URL-safe slug from the organization name.

  Algorithm:
  1. Downcase the name
  2. Replace spaces and special chars with hyphens
  3. Remove consecutive hyphens
  4. Trim hyphens from ends
  5. Append unique suffix to ensure uniqueness
  """
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :slug) do
      changeset
    else
      name = Ash.Changeset.get_attribute(changeset, :name)
      slug = generate_slug(name)
      Ash.Changeset.change_attribute(changeset, :slug, slug)
    end
  end

  defp generate_slug(nil), do: "org-#{unique_suffix()}"
  defp generate_slug(""), do: "org-#{unique_suffix()}"

  defp generate_slug(name) do
    base_slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    case base_slug do
      "" -> "org-#{unique_suffix()}"
      slug -> "#{slug}-#{unique_suffix()}"
    end
  end

  defp unique_suffix do
    :crypto.strong_rand_bytes(4)
    |> Base.encode16(case: :lower)
  end
end
