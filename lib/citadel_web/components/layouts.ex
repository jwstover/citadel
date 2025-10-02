defmodule CitadelWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CitadelWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

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
            <span class="text-xl font-bold">Citadel</span>
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
                <h2>Citadel</h2>
              </div>

              <%!-- Navigation menu --%>
              <ul class="menu-compact">
                <li>
                  <.link navigate={~p"/"} class="flex items-center gap-2">
                    <.icon name="hero-home" class="size-4 text-base-content/70" />
                    <span>Home</span>
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/"} class="flex items-center gap-2">
                    <.icon name="hero-chart-bar" class="size-4 text-base-content/70" />
                    <span>Dashboard</span>
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/"} class="flex items-center gap-2">
                    <.icon name="hero-cog-6-tooth" class="size-4 text-base-content/70" />
                    <span>Settings</span>
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
          <main class="flex-grow bg-base-200 card card-border border-base-300 m-2">
            <div class="card-body py-2 px-6">
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
    <div id={@id} aria-live="polite">
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
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
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
end
