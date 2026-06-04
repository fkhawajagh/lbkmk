defmodule Lbkmk.Reconciliation.PayoutTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Reconciliation.Payout

  describe "changeset/2" do
    @valid_attrs %{
      tenant_id: Ecto.UUID.generate(),
      processor: "stripe",
      processor_payout_id: "po_123",
      gross: Decimal.new("1000.00"),
      net: Decimal.new("970.00"),
      paid_on: ~D[2026-06-01]
    }

    test "valid attributes" do
      changeset = Payout.changeset(%Payout{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid processor" do
      attrs = Map.put(@valid_attrs, :processor, "invalid")
      changeset = Payout.changeset(%Payout{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).processor
    end

    test "invalid state" do
      attrs = Map.put(@valid_attrs, :state, "invalid")
      changeset = Payout.changeset(%Payout{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).state
    end
  end
end
