defmodule Citadel.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Citadel.DataCase, async: true`, although
  this option is not recommended for other databases.

  ## Using Generators

  This module imports `Citadel.Generator` which provides generators
  for all resources using `Ash.Generator`:

      user = generate(user())
      workspace = generate(workspace(actor: user))
      %{workspace: w, owner: o} = generate(workspace_with_owner())

  ## Property-Based Testing

  This module includes ExUnitProperties for property-based testing:

      property "workspace names are always trimmed" do
        check all name <- string(:printable, min_length: 1, max_length: 100) do
          # Test code here
        end
      end

  ## Legacy Helpers

  The existing `create_user/1` and `unique_user_email/0` helpers are
  still available for backward compatibility, but new tests should
  prefer using the generator functions.
  """

  use ExUnit.CaseTemplate

  import Citadel.Generator

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Citadel.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Citadel.DataCase

      # Import Citadel.Generator which re-exports generate/1 and generate_many/2
      # along with all our custom generator functions
      import Citadel.Generator

      # Import ExUnitProperties for property-based testing
      use ExUnitProperties

      # Import Oban testing helpers for job assertions
      use Oban.Testing, repo: Citadel.Repo
    end
  end

  setup tags do
    Citadel.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    # Increase timeout to 60 seconds to prevent timeouts in slower tests
    # especially property-based tests that generate many records
    pid = Sandbox.start_owner!(Citadel.Repo, shared: not tags[:async], timeout: 60_000)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Generates a unique email address for testing.
  """
  def unique_user_email do
    "user-#{System.unique_integer([:positive])}@example.com"
  end

  @doc """
  Creates a user for testing using Ash.Seed.

  ## Examples

      user = create_user()
      user = create_user(%{email: "custom@example.com"})
  """
  def create_user(attrs \\ %{}) do
    generate(user(attrs |> Map.to_list()))
  end

  @doc """
  Helper to add tenant to options if not present.

  This makes it easier to update tests gradually by automatically
  adding tenant from context when available.

  ## Examples

      # In test with workspace in context
      task = Tasks.create_task!(attrs, with_tenant(actor: user, workspace: workspace))
  """
  def with_tenant(opts, context \\ %{}) do
    workspace = Keyword.get(opts, :workspace) || Map.get(context, :workspace)

    if workspace && !Keyword.has_key?(opts, :tenant) do
      opts
      |> Keyword.delete(:workspace)
      |> Keyword.put(:tenant, workspace.id)
    else
      Keyword.delete(opts, :workspace)
    end
  end

  @doc """
  Upgrades an organization to pro tier for testing.

  This is useful for tests that need to add multiple members to an organization,
  as free tier only allows 1 member (the owner).

  ## Examples

      organization = create_organization(owner)
      upgrade_to_pro(organization)
      # Now can add up to 5 members
  """
  def upgrade_to_pro(organization) do
    generate(
      subscription([organization_id: organization.id, tier: :pro, billing_period: :monthly],
        authorize?: false
      )
    )

    organization
  end

  @doc """
  Adds a user to a workspace, automatically ensuring org membership first.

  Since workspaces require users to be organization members, this helper
  adds the user to the workspace's organization (if not already a member)
  before adding them to the workspace.

  ## Options

    * `:actor` - The user performing the action (required)
    * Other options are passed through to `add_workspace_member!`

  ## Examples

      add_user_to_workspace(other_user.id, workspace.id, actor: owner)
  """
  def add_user_to_workspace(user_id, workspace_id, opts \\ []) do
    require Ash.Query

    workspace =
      Citadel.Accounts.Workspace
      |> Ash.Query.filter(id == ^workspace_id)
      |> Ash.Query.select([:organization_id])
      |> Ash.read_one!(authorize?: false)

    if workspace.organization_id do
      unless user_is_org_member?(user_id, workspace.organization_id) do
        Citadel.Accounts.add_organization_member(
          workspace.organization_id,
          user_id,
          :member,
          authorize?: false
        )
      end
    end

    Citadel.Accounts.add_workspace_member!(user_id, workspace_id, opts)
  end

  defp user_is_org_member?(user_id, organization_id) do
    require Ash.Query

    Citadel.Accounts.OrganizationMembership
    |> Ash.Query.filter(user_id == ^user_id and organization_id == ^organization_id)
    |> Ash.exists?(authorize?: false)
  end
end
