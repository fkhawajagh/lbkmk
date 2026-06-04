defmodule Lbkmk.Repo.Migrations.CreateAuditLog do
  use Ecto.Migration

  def change do
    create table(:audit_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :actor_type, :string, null: false
      add :actor_id, :string
      add :subject_type, :string, null: false
      add :subject_id, :string, null: false
      add :action, :string, null: false
      add :metadata, :map, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_log, [:tenant_id, :subject_type, :subject_id])
    create index(:audit_log, [:tenant_id, :occurred_at])
    create index(:audit_log, [:tenant_id, :actor_type, :actor_id])
  end
end
