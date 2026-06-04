defmodule LbkmkWeb.DashboardLive.SkusTest do
  use LbkmkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "mounts without crash", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/skus")
    assert html =~ "Channel SKUs"
  end
end
