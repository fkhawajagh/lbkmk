defmodule LbkmkWeb.PageController do
  use LbkmkWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
