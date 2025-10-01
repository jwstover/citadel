defmodule CitadelWeb.PageController do
  use CitadelWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
