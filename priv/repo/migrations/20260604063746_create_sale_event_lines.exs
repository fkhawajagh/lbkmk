defmodule Lbkmk.Repo.Migrations.CreateSaleEventLines do
  use Ecto.Migration

  def change do
    create table(:sale_event_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false

      add :sale_event_id, references(:sale_events, type: :binary_id, on_delete: :delete_all),
        null: false

      add :channel_sku_id, :binary_id
      add :quantity, :integer, null: false
      add :unit_price, :decimal, null: false
      add :subtotal, :decimal, null: false
      add :line_index, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:sale_event_lines, [:tenant_id, :sale_event_id])
  end
end
