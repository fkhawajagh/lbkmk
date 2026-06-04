defmodule Lbkmk.IngestTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Ingest

  describe "upsert_event/1" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = Ingest.upsert_event(%{})
    end
  end

  describe "resolve_lines/1" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = Ingest.resolve_lines(%Lbkmk.Ingest.SaleEvent{})
    end
  end
end
