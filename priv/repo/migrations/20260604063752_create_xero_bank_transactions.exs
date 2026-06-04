defmodule Lbkmk.Repo.Migrations.CreateXeroBankTransactions do
  use Ecto.Migration

  def change do
    create table(:xero_bank_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false

      add :sale_event_id, references(:sale_events, type: :binary_id, on_delete: :delete_all),
        null: false

      add :xero_bank_transaction_id, :string, null: false
      add :xero_reference, :string, null: false
      add :posted_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:xero_bank_transactions, [:tenant_id, :xero_bank_transaction_id])
    create unique_index(:xero_bank_transactions, [:tenant_id, :sale_event_id])
    create index(:xero_bank_transactions, [:tenant_id, :posted_at])
  end
end
