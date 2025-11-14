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
    pid = Sandbox.start_owner!(Citadel.Repo, shared: not tags[:async])
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
    email = Map.get(attrs, :email, unique_user_email())

    Ash.Seed.seed!(Citadel.Accounts.User, %{email: email})
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
end
