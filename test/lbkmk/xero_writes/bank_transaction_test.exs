defmodule Lbkmk.XeroWrites.BankTransactionTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.XeroWrites.BankTransaction

  describe "changeset/2" do
    @valid_attrs %{
      tenant_id: Ecto.UUID.generate(),
      sale_event_id: Ecto.UUID.generate(),
      xero_bank_transaction_id: "bt-123",
      xero_reference: "lbkmk:evt-456",
      posted_at: DateTime.utc_now()
    }

    test "valid attributes" do
      changeset = BankTransaction.changeset(%BankTransaction{}, @valid_attrs)
      assert changeset.valid?
    end

    test "missing required fields" do
      changeset = BankTransaction.changeset(%BankTransaction{}, %{})
      refute changeset.valid?
      assert errors_on(changeset).xero_bank_transaction_id
      assert errors_on(changeset).xero_reference
    end
  end
end
