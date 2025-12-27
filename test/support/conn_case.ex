defmodule CitadelWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CitadelWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  import Citadel.Generator

  using do
    quote do
      # The default endpoint for testing
      @endpoint CitadelWeb.Endpoint

      use CitadelWeb, :verified_routes
      use Oban.Testing, repo: Citadel.Repo

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import CitadelWeb.ConnCase

      # Import generators for test data
      import Citadel.Generator

      # Import helper functions from DataCase
      import Citadel.DataCase, only: [add_user_to_workspace: 3, upgrade_to_pro: 1]
    end
  end

  setup tags do
    Citadel.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Registers and logs in a user for testing authenticated LiveViews.

  ## Usage

      setup :register_and_log_in_user

  Or call directly in a test:

      test "authenticated page", %{conn: conn} do
        %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
        # ... test code
      end
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = Citadel.DataCase.create_user()
    workspace = generate(workspace([], actor: user))

    conn = log_in_user(conn, user)

    Map.merge(context, %{conn: conn, user: user, workspace: workspace})
  end

  @doc """
  Logs in the given user without going through authentication.
  """
  def log_in_user(conn, user) do
    {:ok, token, _} =
      AshAuthentication.Jwt.token_for_user(user, %{},
        purpose: :user,
        token_lifetime: {1, :hours}
      )

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
