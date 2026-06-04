defmodule LbkmkWeb.API.XeroWriteResultController do
  use LbkmkWeb, :controller

  alias Lbkmk.XeroWrites

  def create(conn, params) do
    # TODO: wire XeroWrites.handle_result/1 once implemented
    _ = XeroWrites.handle_result(params)

    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "not_implemented"})
  end
end
