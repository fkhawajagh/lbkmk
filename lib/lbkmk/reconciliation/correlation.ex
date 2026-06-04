defmodule Lbkmk.Reconciliation.Correlation do
  @moduledoc """
  Schema pairing a sale-side event with its payment-side event.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "correlations" do
    field :tenant_id, Ecto.UUID
    field :confidence, :string
    field :strategy, :string

    belongs_to :primary_sale_event, Lbkmk.Ingest.SaleEvent, type: :binary_id
    belongs_to :payment_sale_event, Lbkmk.Ingest.SaleEvent, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @confidences ~w(high medium low)
  @strategies ~w(id_match metadata_match amount_time_window)

  @doc false
  def changeset(correlation, attrs) do
    correlation
    |> cast(attrs, [
      :tenant_id,
      :primary_sale_event_id,
      :payment_sale_event_id,
      :confidence,
      :strategy
    ])
    |> validate_required([:tenant_id, :primary_sale_event_id, :payment_sale_event_id, :confidence, :strategy])
    |> validate_inclusion(:confidence, @confidences)
    |> validate_inclusion(:strategy, @strategies)
    |> unique_constraint([:tenant_id, :primary_sale_event_id, :payment_sale_event_id])
    |> foreign_key_constraint(:primary_sale_event_id)
    |> foreign_key_constraint(:payment_sale_event_id)
  end
end
