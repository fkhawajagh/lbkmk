defmodule LbkmkWeb.API.SaleEventControllerTest do
  use LbkmkWeb.ConnCase, async: true

  describe "POST /api/v1/sale-events" do
    test "returns not_implemented", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/sale-events", %{channel: "squarespace", external_event_id: "ord_1"})

      assert json_response(conn, 503)["error"] == "not_implemented"
    end
  end

  describe "GET /api/v1/sale-events" do
    test "returns empty list", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/sale-events")
      assert json_response(conn, 200)["sale_events"] == []
    end
  end
end
