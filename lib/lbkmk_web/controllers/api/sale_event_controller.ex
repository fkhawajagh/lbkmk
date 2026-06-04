defmodule LbkmkWeb.API.SaleEventController do
  use LbkmkWeb, :controller

  alias Lbkmk.Ingest

  def create(conn, params) do
    # TODO: wire Ingest.upsert_event/1 once implemented
    _ = Ingest.upsert_event(params)

    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "not_implemented"})
  end

  def index(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{sale_events: []})
  end
end
