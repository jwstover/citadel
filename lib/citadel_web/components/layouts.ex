defmodule CitadelWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CitadelWeb, :html

  import CitadelWeb.Components.WorkspaceSwitcher

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_workspace, :map, default: nil, doc: "the current workspace"
  attr :workspaces, :list, default: [], doc: "list of all user's workspaces"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex flex-col">
        <%!-- Navbar --%>
        <div class="navbar bg-base-200 lg:hidden">
          <div class="flex-none">
            <label for="sidebar-drawer" class="btn btn-square btn-ghost">
              <.icon name="hero-bars-3" class="size-6" />
            </label>
          </div>
          <div class="flex-1">
            <span class="text-xl font-bold">Pyllar</span>
          </div>
        </div>

        <div class="flex h-screen w-screen">
          <div>
            <label for="sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
            <div class="menu bg-base-100 text-base-content min-h-full w-56 p-2">
              <%!-- Sidebar header --%>
              <div class="mb-6 mt-2 px-2 gap-3 flex flex-row items-center">
                <div class="btn btn-primary btn-square btn-sm pointer-events-none">
                  <.icon name="hero-building-library" class="size-4" />
                </div>
                <h2>Pyllar</h2>
              </div>

              <%!-- Workspace switcher --%>
              <%= if @current_workspace && @workspaces != [] do %>
                <div class="mb-4 px-2">
                  <.workspace_switcher
                    current_workspace={@current_workspace}
                    workspaces={@workspaces}
                  />
                </div>
              <% end %>

              <%!-- Navigation menu --%>
              <ul class="menu-compact">
                <li>
                  <.link navigate={~p"/dashboard"} class="flex items-center gap-2">
                    <.icon name="hero-home" class="size-4 text-base-content/70" />
                    <span>Home</span>
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/dashboard"} class="flex items-center gap-2">
                    <.icon name="hero-chart-bar" class="size-4 text-base-content/70" />
                    <span>Dashboard</span>
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/preferences"} class="flex items-center gap-2">
                    <.icon name="hero-cog-6-tooth" class="size-4 text-base-content/70" />
                    <span>Preferences</span>
                  </.link>
                </li>
              </ul>

              <%!-- Theme toggle --%>
              <div class="mt-auto pt-4 flex justify-center">
                <div class="max-w-max">
                  <.theme_toggle />
                </div>
              </div>
            </div>
          </div>

          <%!-- Main content --%>
          <main class="flex-grow py-4 px-4 h-full w-full overflow-hidden">
            <div class="card-body p-0 h-full w-full overflow-hidden">
              {render_slot(@inner_block)}
            </div>
          </main>
        </div>

        <.flash_group flash={@flash} />
      </div>

      <%!-- Sidebar --%>
      <div class="drawer-side"></div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="z-100">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a public layout for pages that don't require authentication.

  Used for legal pages (Terms of Service, Privacy Policy) and other public content.

  ## Examples

      <Layouts.public>
        <h1>Content</h1>
      </Layouts.public>

  """
  attr :flash, :map, default: %{}, doc: "the map of flash messages"
  slot :inner_block, required: true

  def public(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 flex flex-col">
      <header class="bg-base-200 border-b border-base-300">
        <div class="container mx-auto px-4 py-3 flex items-center justify-between">
          <a href="/" class="flex items-center gap-2">
            <div class="btn btn-primary btn-square btn-sm pointer-events-none">
              <.icon name="hero-building-library" class="size-4" />
            </div>
            <span class="text-xl font-bold">Pyllar</span>
          </a>
          <a href="/sign-in" class="btn btn-ghost btn-sm">Sign In</a>
        </div>
      </header>

      <main class="container mx-auto px-4 py-8 max-w-4xl flex-1">
        {render_slot(@inner_block)}
      </main>

      <footer class="footer footer-center p-4 bg-base-200 text-base-content border-t border-base-300">
        <div class="flex flex-wrap justify-center gap-4 text-sm">
          <a href="/terms" class="link link-hover">Terms of Service</a>
          <a href="/privacy" class="link link-hover">Privacy Policy</a>
        </div>
        <p class="text-xs text-base-content/60">
          &copy; {DateTime.utc_now().year} Pyllar. All rights reserved.
        </p>
      </footer>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-border bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=citadel-light]_&]:left-1/3 [[data-theme=citadel-dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="citadel-light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="citadel-dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  @doc """
  Renders the marketing layout for public pages like the landing page.

  This layout features a clean navigation header without the sidebar,
  optimized for marketing and conversion.

  ## Examples

      <Layouts.marketing flash={@flash} current_user={@current_user}>
        <section>Hero content</section>
      </Layouts.marketing>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil, doc: "the current user, if authenticated"

  slot :inner_block, required: true

  def marketing(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 relative overflow-x-hidden">
      <div class="fixed inset-0 pointer-events-none overflow-hidden">
        <div class="absolute -top-1/2 -right-1/4 w-[800px] h-[800px] rounded-full bg-gradient-to-br from-primary/5 to-transparent blur-3xl" />
        <div class="absolute top-1/3 -left-1/4 w-[600px] h-[600px] rounded-full bg-gradient-to-tr from-accent/5 to-transparent blur-3xl" />
      </div>

      <header class="fixed top-0 left-0 right-0 z-50 backdrop-blur-xl bg-base-100/80 border-b border-base-300/50">
        <nav class="container mx-auto px-6 lg:px-8">
          <div class="flex items-center justify-between h-16 lg:h-20">
            <.link navigate={~p"/"} class="flex items-center gap-3 group">
              <div class="relative">
                <div class="absolute inset-0 bg-primary/20 blur-lg rounded-lg opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
                <div class="relative btn btn-primary btn-square btn-sm pointer-events-none">
                  <.icon name="hero-building-library" class="size-4" />
                </div>
              </div>
              <span class="text-xl font-bold tracking-tight">Citadel</span>
            </.link>

            <div class="hidden md:flex items-center gap-8">
              <a
                href="#features"
                class="text-sm font-medium text-base-content/70 hover:text-base-content transition-colors duration-200 relative after:absolute after:bottom-0 after:left-0 after:w-0 after:h-px after:bg-primary hover:after:w-full after:transition-all after:duration-300"
              >
                Features
              </a>
              <a
                href="#pricing"
                class="text-sm font-medium text-base-content/70 hover:text-base-content transition-colors duration-200 relative after:absolute after:bottom-0 after:left-0 after:w-0 after:h-px after:bg-primary hover:after:w-full after:transition-all after:duration-300"
              >
                Pricing
              </a>
            </div>

            <div class="flex items-center gap-3">
              <div class="hidden sm:block">
                <.theme_toggle />
              </div>
              <%= if @current_user do %>
                <.link
                  navigate={~p"/dashboard"}
                  class="btn btn-primary btn-sm px-5 font-medium shadow-lg shadow-primary/20 hover:shadow-primary/30 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200"
                >
                  Go to Dashboard <.icon name="hero-arrow-right-micro" class="size-4" />
                </.link>
              <% else %>
                <.link
                  navigate={~p"/sign-in"}
                  class="btn btn-ghost btn-sm font-medium text-base-content/70 hover:text-base-content"
                >
                  Sign In
                </.link>
                <.link
                  navigate={~p"/register"}
                  class="btn btn-primary btn-sm px-5 font-medium shadow-lg shadow-primary/20 hover:shadow-primary/30 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200"
                >
                  Start Planning
                </.link>
              <% end %>
            </div>
          </div>
        </nav>
      </header>

      <main class="pt-16 lg:pt-20">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end
  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"
end
