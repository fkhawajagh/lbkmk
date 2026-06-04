defmodule Lbkmk.Inventory do
  @moduledoc """
  Context for mirroring Xero tracked items and managing channel SKU mappings.
  """

  alias Lbkmk.Inventory.Item

  @doc """
  Replaces the local inventory snapshot with data from Xero.
  """
  @spec snapshot_from_xero(list(map())) :: {:ok, term()} | {:error, atom()}
  def snapshot_from_xero(_items) do
    {:error, :not_implemented}
  end

  @doc """
  Looks up an inventory item by its Xero item code.
  """
  @spec item_by_xero_code(String.t()) :: {:ok, Item.t()} | {:error, :not_found}
  def item_by_xero_code(_xero_item_code) do
    {:error, :not_implemented}
  end

  @doc """
  Upserts a channel SKU record.
  """
  @spec upsert_sku(map()) :: {:ok, term()} | {:error, Ecto.Changeset.t()}
  def upsert_sku(_attrs) do
    {:error, :not_implemented}
  end

  @doc """
  Maps an unmapped channel SKU to a canonical inventory item.
  """
  @spec map_to_item(String.t(), String.t()) :: {:ok, term()} | {:error, atom()}
  def map_to_item(_channel_sku_id, _inventory_item_id) do
    {:error, :not_implemented}
  end
end
