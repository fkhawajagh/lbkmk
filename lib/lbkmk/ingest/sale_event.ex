defmodule Lbkmk.Ingest.SaleEvent do
  @moduledoc """
  Schema for a sale event — a single record of channel activity.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sale_events" do
    field :tenant_id, Ecto.UUID
    field :channel, :string
    field :external_event_id, :string
    field :occurred_at, :utc_datetime_usec
    field :gross, :decimal
    field :fee, :decimal
    field :net, :decimal
    field :currency, :string, default: "AUD"
    field :state, :string, default: "pending"
    field :state_reason, :string
    field :raw_payload, :binary
    field :stripe_charge_id, :string

    has_many :lines, Lbkmk.Ingest.SaleEventLine

    timestamps(type: :utc_datetime_usec)
  end

  @channels ~w(squarespace stripe square tickettailor)
  @states ~w(pending needs_resolution approved posting posted failed rejected voided)

  @doc false
  def changeset(sale_event, attrs) do
    sale_event
    |> cast(attrs, [
      :tenant_id,
      :channel,
      :external_event_id,
      :occurred_at,
      :gross,
      :fee,
      :net,
      :currency,
      :state,
      :state_reason,
      :raw_payload,
      :stripe_charge_id
    ])
    |> validate_required([
      :tenant_id,
      :channel,
      :external_event_id,
      :occurred_at,
      :gross,
      :net,
      :currency
    ])
    |> validate_inclusion(:channel, @channels)
    |> validate_inclusion(:state, @states)
    |> unique_constraint([:tenant_id, :channel, :external_event_id])
  end
end
