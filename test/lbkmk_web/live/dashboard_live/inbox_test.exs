defmodule LbkmkWeb.DashboardLive.InboxTest do
  use LbkmkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "mounts without crash", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/inbox")
    assert html =~ "Inbox"
  end
end
