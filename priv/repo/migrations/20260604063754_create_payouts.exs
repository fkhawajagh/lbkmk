defmodule Lbkmk.Repo.Migrations.CreatePayouts do
  use Ecto.Migration

  def change do
    create table(:payouts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :processor, :string, null: false
      add :processor_payout_id, :string, null: false
      add :gross, :decimal, null: false
      add :fee, :decimal
      add :net, :decimal, null: false
      add :paid_on, :date, null: false
      add :state, :string, null: false, default: "received"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:payouts, [:tenant_id, :processor, :processor_payout_id])
    create index(:payouts, [:tenant_id, :paid_on])
    create index(:payouts, [:tenant_id, :state])
  end
end
