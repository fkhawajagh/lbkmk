defmodule LbkmkWeb.API.XeroWriteResultControllerTest do
  use LbkmkWeb.ConnCase, async: true

  describe "POST /api/v1/xero-write-result" do
    test "returns not_implemented", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/xero-write-result", %{sale_event_id: "evt-1", status: "success"})
      assert json_response(conn, 503)["error"] == "not_implemented"
    end
  end
end
