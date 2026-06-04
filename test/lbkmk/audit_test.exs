defmodule Lbkmk.AuditTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Audit

  describe "record/4" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} =
               Audit.record("system", nil, {"sale_event", "evt-1"})
    end
  end

  describe "timeline_for/1" do
    test "returns empty list" do
      assert [] = Audit.timeline_for({"sale_event", "evt-1"})
    end
  end
end
