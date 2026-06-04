defmodule Lbkmk.Reconciliation.CorrelationTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Reconciliation.Correlation

  describe "changeset/2" do
    @valid_attrs %{
      tenant_id: Ecto.UUID.generate(),
      primary_sale_event_id: Ecto.UUID.generate(),
      payment_sale_event_id: Ecto.UUID.generate(),
      confidence: "high",
      strategy: "id_match"
    }

    test "valid attributes" do
      changeset = Correlation.changeset(%Correlation{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid confidence" do
      attrs = Map.put(@valid_attrs, :confidence, "invalid")
      changeset = Correlation.changeset(%Correlation{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).confidence
    end

    test "invalid strategy" do
      attrs = Map.put(@valid_attrs, :strategy, "invalid")
      changeset = Correlation.changeset(%Correlation{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).strategy
    end
  end
end
