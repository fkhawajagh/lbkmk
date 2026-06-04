defmodule Lbkmk.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :email, :string, null: false
      add :role, :string, null: false, default: "owner"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:tenant_id, :email])
  end
end
