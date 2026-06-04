defmodule Lbkmk.Audit.LogEntryTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Audit.LogEntry

  describe "changeset/2" do
    @valid_attrs %{
      tenant_id: Ecto.UUID.generate(),
      actor_type: "system",
      subject_type: "sale_event",
      subject_id: "evt-123",
      action: "state_transition",
      occurred_at: DateTime.utc_now()
    }

    test "valid attributes" do
      changeset = LogEntry.changeset(%LogEntry{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid actor_type" do
      attrs = Map.put(@valid_attrs, :actor_type, "invalid")
      changeset = LogEntry.changeset(%LogEntry{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).actor_type
    end
  end
end
