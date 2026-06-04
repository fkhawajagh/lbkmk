defmodule Lbkmk.Repo.Migrations.CreateChannelSkus do
  use Ecto.Migration

  def change do
    create table(:channel_skus, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :inventory_item_id, references(:inventory_items, type: :binary_id, on_delete: :nilify_all)
      add :channel, :string, null: false
      add :external_id, :string, null: false
      add :external_name, :string
      add :state, :string, null: false, default: "unmapped"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channel_skus, [:tenant_id, :channel, :external_id])
    create index(:channel_skus, [:tenant_id, :inventory_item_id])
    create index(:channel_skus, [:tenant_id, :state])
  end
end
