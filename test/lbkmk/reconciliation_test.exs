defmodule Lbkmk.ReconciliationTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Reconciliation

  describe "try_correlate/1" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = Reconciliation.try_correlate(%Lbkmk.Ingest.SaleEvent{})
    end
  end

  describe "approve/2" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} =
               Reconciliation.approve(%Lbkmk.Ingest.SaleEvent{}, "user-1")
    end
  end

  describe "reject/2" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} =
               Reconciliation.reject(%Lbkmk.Ingest.SaleEvent{}, "user-1")
    end
  end

  describe "sweep_payouts/0" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = Reconciliation.sweep_payouts()
    end
  end
end
