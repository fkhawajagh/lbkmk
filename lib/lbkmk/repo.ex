defmodule Lbkmk.Repo do
  use Ecto.Repo,
    otp_app: :lbkmk,
    adapter: Ecto.Adapters.Postgres
end
