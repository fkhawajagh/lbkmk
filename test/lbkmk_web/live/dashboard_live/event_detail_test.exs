defmodule LbkmkWeb.DashboardLive.EventDetailTest do
  use LbkmkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "mounts without crash", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/events/evt-123")
    assert html =~ "Event Detail"
  end
end
