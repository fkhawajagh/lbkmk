defmodule Lbkmk.XeroWritesTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.XeroWrites

  describe "dispatch/1" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = XeroWrites.dispatch(%Lbkmk.Ingest.SaleEvent{})
    end
  end

  describe "handle_result/1" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = XeroWrites.handle_result(%{})
    end
  end
end
