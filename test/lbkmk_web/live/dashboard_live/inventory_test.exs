defmodule LbkmkWeb.DashboardLive.InventoryTest do
  use LbkmkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "mounts without crash", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/inventory")
    assert html =~ "Inventory"
  end
end
