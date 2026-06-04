defmodule Lbkmk.Repo.Migrations.CreateInventoryItems do
  use Ecto.Migration

  def change do
    create table(:inventory_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :xero_item_code, :string, null: false
      add :name, :string, null: false
      add :kind, :string, null: false
      add :current_stock, :integer, null: false, default: 0
      add :unit_cost, :decimal
      add :revenue_account_code, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:inventory_items, [:tenant_id, :xero_item_code])
    create index(:inventory_items, [:tenant_id, :kind])
  end
end
