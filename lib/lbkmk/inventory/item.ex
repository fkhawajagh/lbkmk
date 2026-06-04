defmodule Lbkmk.Inventory.Item do
  @moduledoc """
  Schema for a canonical inventory item, mirrored from Xero.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "inventory_items" do
    field :tenant_id, Ecto.UUID
    field :xero_item_code, :string
    field :name, :string
    field :kind, :string
    field :current_stock, :integer, default: 0
    field :unit_cost, :decimal
    field :revenue_account_code, :string

    has_many :channel_skus, Lbkmk.Inventory.ChannelSku, foreign_key: :inventory_item_id

    timestamps(type: :utc_datetime_usec)
  end

  @kinds ~w(merch ticket)

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:tenant_id, :xero_item_code, :name, :kind, :current_stock, :unit_cost, :revenue_account_code])
    |> validate_required([:tenant_id, :xero_item_code, :name, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:current_stock, greater_than_or_equal_to: 0)
    |> unique_constraint([:tenant_id, :xero_item_code])
  end
end
