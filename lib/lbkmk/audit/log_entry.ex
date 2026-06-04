defmodule Lbkmk.Audit.LogEntry do
  @moduledoc """
  Schema for an append-only audit log entry.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "audit_log" do
    field :tenant_id, Ecto.UUID
    field :actor_type, :string
    field :actor_id, :string
    field :subject_type, :string
    field :subject_id, :string
    field :action, :string
    field :metadata, :map, default: %{}
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @actor_types ~w(system user)

  @doc false
  def changeset(log_entry, attrs) do
    log_entry
    |> cast(attrs, [
      :tenant_id,
      :actor_type,
      :actor_id,
      :subject_type,
      :subject_id,
      :action,
      :metadata,
      :occurred_at
    ])
    |> validate_required([
      :tenant_id,
      :actor_type,
      :subject_type,
      :subject_id,
      :action,
      :occurred_at
    ])
    |> validate_inclusion(:actor_type, @actor_types)
  end
end
