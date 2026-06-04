defmodule Lbkmk.Inventory.ChannelSku do
  @moduledoc """
  Schema mapping a channel's external product ID to a canonical inventory item.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "channel_skus" do
    field :tenant_id, Ecto.UUID
    field :channel, :string
    field :external_id, :string
    field :external_name, :string
    field :state, :string, default: "unmapped"

    belongs_to :inventory_item, Lbkmk.Inventory.Item, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @channels ~w(squarespace stripe square tickettailor)
  @states ~w(unmapped mapped retired)

  @doc false
  def changeset(channel_sku, attrs) do
    channel_sku
    |> cast(attrs, [:tenant_id, :inventory_item_id, :channel, :external_id, :external_name, :state])
    |> validate_required([:tenant_id, :channel, :external_id])
    |> validate_inclusion(:channel, @channels)
    |> validate_inclusion(:state, @states)
    |> unique_constraint([:tenant_id, :channel, :external_id])
    |> foreign_key_constraint(:inventory_item_id)
  end
end
