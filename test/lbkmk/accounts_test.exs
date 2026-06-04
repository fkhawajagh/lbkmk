defmodule Lbkmk.AccountsTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Accounts

  describe "get_user/1" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = Accounts.get_user("user-1")
    end
  end

  describe "register_user/1" do
    test "returns not_implemented" do
      assert {:error, :not_implemented} = Accounts.register_user(%{})
    end
  end
end
