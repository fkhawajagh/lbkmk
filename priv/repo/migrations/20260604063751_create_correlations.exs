defmodule Lbkmk.Repo.Migrations.CreateCorrelations do
  use Ecto.Migration

  def change do
    create table(:correlations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false

      add :primary_sale_event_id,
          references(:sale_events, type: :binary_id, on_delete: :delete_all), null: false

      add :payment_sale_event_id,
          references(:sale_events, type: :binary_id, on_delete: :delete_all), null: false

      add :confidence, :string, null: false
      add :strategy, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:correlations, [
             :tenant_id,
             :primary_sale_event_id,
             :payment_sale_event_id
           ])

    create index(:correlations, [:tenant_id, :primary_sale_event_id])
    create index(:correlations, [:tenant_id, :payment_sale_event_id])
  end
end
