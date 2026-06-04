defmodule Lbkmk.InventoryTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Inventory

  describe "snapshot_from_xero/1" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = Inventory.snapshot_from_xero([])
    end
  end

  describe "item_by_xero_code/1" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = Inventory.item_by_xero_code("TSHIRT-RED-L")
    end
  end

  describe "upsert_sku/1" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = Inventory.upsert_sku(%{})
    end
  end

  describe "map_to_item/2" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = Inventory.map_to_item("sku-1", "item-1")
    end
  end
end
