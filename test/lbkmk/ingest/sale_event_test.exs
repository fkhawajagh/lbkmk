defmodule Lbkmk.Ingest.SaleEventTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Ingest.SaleEvent

  describe "changeset/2" do
    @valid_attrs %{
      tenant_id: Ecto.UUID.generate(),
      channel: "squarespace",
      external_event_id: "ord_123",
      occurred_at: DateTime.utc_now(),
      gross: Decimal.new("100.00"),
      net: Decimal.new("97.00"),
      currency: "AUD"
    }

    test "valid attributes" do
      changeset = SaleEvent.changeset(%SaleEvent{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid channel" do
      attrs = Map.put(@valid_attrs, :channel, "invalid")
      changeset = SaleEvent.changeset(%SaleEvent{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).channel
    end

    test "invalid state" do
      attrs = Map.put(@valid_attrs, :state, "invalid")
      changeset = SaleEvent.changeset(%SaleEvent{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).state
    end

    test "missing required fields" do
      changeset = SaleEvent.changeset(%SaleEvent{}, %{})
      refute changeset.valid?
      assert errors_on(changeset).tenant_id
      assert errors_on(changeset).channel
      assert errors_on(changeset).external_event_id
    end
  end
end
