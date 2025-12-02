defmodule CitadelWeb.Router do
  use CitadelWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CitadelWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data:; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self' ws: wss:;"
    }

    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user

    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: Citadel.Accounts.User,
      required?: true
  end

  pipeline :mcp do
    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: Citadel.Accounts.User,
      required?: true
  end

  scope "/", CitadelWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      live "/chat", ChatLive
      live "/chat/:conversation_id", ChatLive
      live "/", HomeLive.Index, :index
      live "/tasks/:id", TaskLive.Show, :show
      live "/preferences", PreferencesLive.Index, :index
      live "/preferences/workspaces/new", PreferencesLive.WorkspaceForm, :new
      live "/preferences/workspaces/:id/edit", PreferencesLive.WorkspaceForm, :edit
      live "/preferences/workspace/:id", PreferencesLive.Workspace, :show
      live "/preferences/api-keys/new", PreferencesLive.ApiKeyNew, :new
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {CitadelWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {CitadelWeb.LiveUserAuth, :live_no_user}
    end

    # Public routes (no authentication required)
    ash_authentication_live_session :public_routes do
      live "/invitations/:token", InvitationLive.Accept, :show
    end
  end

  scope "/mcp" do
    pipe_through :mcp

    forward "/", AshAi.Mcp.Router,
      tools: [
        :list_tasks,
        :create_task,
        :update_task,
        :list_task_states
      ],
      # For many tools, you will need to set the `protocol_version_statement` to the older version.
      protocol_version_statement: "2024-11-05",
      otp_app: :citadel
  end

  scope "/", CitadelWeb do
    pipe_through :browser

    # Workspace session management
    get "/workspaces/switch/:workspace_id", WorkspaceController, :switch

    auth_routes AuthController, Citadel.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{CitadelWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    CitadelWeb.AuthOverrides,
                    AshAuthentication.Phoenix.Overrides.Default
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [CitadelWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the confirmation strategy
    confirm_route Citadel.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [CitadelWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Citadel.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [CitadelWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", CitadelWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:citadel, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CitadelWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:citadel, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
