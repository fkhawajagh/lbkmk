defmodule Lbkmk.Repo.Migrations.CreateSaleEvents do
  use Ecto.Migration

  def change do
    create table(:sale_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :channel, :string, null: false
      add :external_event_id, :string, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :gross, :decimal, null: false
      add :fee, :decimal
      add :net, :decimal, null: false
      add :currency, :string, null: false, default: "AUD"
      add :state, :string, null: false, default: "pending"
      add :state_reason, :string
      add :raw_payload, :binary
      add :stripe_charge_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sale_events, [:tenant_id, :channel, :external_event_id])
    create index(:sale_events, [:tenant_id, :state])
    create index(:sale_events, [:tenant_id, :channel])
    create index(:sale_events, [:tenant_id, :occurred_at])
  end
end
