defmodule CitadelWeb.HomeLive.Index do
  @moduledoc false

  use CitadelWeb, :live_view

  import CitadelWeb.Components.TodoComponents

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.control_bar />

      <div class="">
        <.todos_list />
      </div>
    </Layouts.app>
    """
  end
end
