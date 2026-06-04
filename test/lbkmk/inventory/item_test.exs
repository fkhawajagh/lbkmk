defmodule Lbkmk.Inventory.ItemTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Inventory.Item

  describe "changeset/2" do
    @valid_attrs %{
      tenant_id: Ecto.UUID.generate(),
      xero_item_code: "TSHIRT-RED-L",
      name: "LBK T-shirt (red, large)",
      kind: "merch"
    }

    test "valid attributes" do
      changeset = Item.changeset(%Item{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid kind" do
      attrs = Map.put(@valid_attrs, :kind, "invalid")
      changeset = Item.changeset(%Item{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).kind
    end

    test "negative stock" do
      attrs = Map.put(@valid_attrs, :current_stock, -1)
      changeset = Item.changeset(%Item{}, attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).current_stock
    end
  end
end
