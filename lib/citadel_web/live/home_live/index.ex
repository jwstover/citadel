defmodule CitadelWeb.HomeLive.Index do
  @moduledoc false

  use CitadelWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      CitadelWeb.HomeLive.Index
    </Layouts.app>
    """
  end
end
