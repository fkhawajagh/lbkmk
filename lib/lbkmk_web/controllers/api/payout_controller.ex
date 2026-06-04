defmodule LbkmkWeb.API.PayoutController do
  use LbkmkWeb, :controller

  def create(conn, _params) do
    conn
    |> put_status(:created)
    |> json(%{status: "acknowledged"})
  end
end
