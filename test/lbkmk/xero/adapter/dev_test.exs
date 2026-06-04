defmodule Lbkmk.Xero.Adapter.DevTest do
  use ExUnit.Case, async: true

  alias Lbkmk.Xero.Adapter.Dev

  describe "post_bank_transaction/1" do
    test "returns a synthetic BankTransactionID" do
      assert {:ok, %{"BankTransactionID" => id}} = Dev.post_bank_transaction(%{test: true})
      assert is_binary(id)
      assert String.starts_with?(id, "dev-bt-")
    end
  end

  describe "get_bank_transaction/1" do
    test "returns the requested ID back" do
      assert {:ok, %{"BankTransactionID" => "bt-123"}} = Dev.get_bank_transaction("bt-123")
    end
  end

  describe "list_items/0" do
    test "returns a synthetic item list" do
      assert {:ok, [%{"ItemCode" => "DEV-ITEM-1"}]} = Dev.list_items()
    end
  end
end
