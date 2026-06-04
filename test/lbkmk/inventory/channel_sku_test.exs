defmodule Lbkmk.Inventory.ChannelSkuTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Inventory.ChannelSku

  describe "changeset/2" do
    @valid_attrs %{
      tenant_id: Ecto.UUID.generate(),
      channel: "squarespace",
      external_id: "var_abc123"
    }

    test "valid attributes" do
      changeset = ChannelSku.changeset(%ChannelSku{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid state" do
      attrs = Map.put(@valid_attrs, :state, "invalid")
      changeset = ChannelSku.changeset(%ChannelSku{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).state
    end
  end
end
