defmodule Lbkmk.Ingest.SaleEventLine do
  @moduledoc """
  Schema for a line item within a sale event.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sale_event_lines" do
    field :tenant_id, Ecto.UUID
    field :quantity, :integer
    field :unit_price, :decimal
    field :subtotal, :decimal
    field :line_index, :integer

    belongs_to :sale_event, Lbkmk.Ingest.SaleEvent, type: :binary_id
    belongs_to :channel_sku, Lbkmk.Inventory.ChannelSku, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(line, attrs) do
    line
    |> cast(attrs, [
      :tenant_id,
      :sale_event_id,
      :channel_sku_id,
      :quantity,
      :unit_price,
      :subtotal,
      :line_index
    ])
    |> validate_required([
      :tenant_id,
      :sale_event_id,
      :quantity,
      :unit_price,
      :subtotal,
      :line_index
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:line_index, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:sale_event_id)
    |> foreign_key_constraint(:channel_sku_id)
  end
end
