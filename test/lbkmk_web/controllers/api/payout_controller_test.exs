defmodule LbkmkWeb.API.PayoutControllerTest do
  use LbkmkWeb.ConnCase, async: true

  describe "POST /api/v1/payouts" do
    test "returns acknowledged", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/payouts", %{processor: "stripe", processor_payout_id: "po_1"})
      assert json_response(conn, 201)["status"] == "acknowledged"
    end
  end
end
