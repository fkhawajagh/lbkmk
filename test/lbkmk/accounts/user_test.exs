defmodule Lbkmk.Accounts.UserTest do
  use Lbkmk.DataCase, async: true

  alias Lbkmk.Accounts.User

  describe "changeset/2" do
    @valid_attrs %{
      tenant_id: Ecto.UUID.generate(),
      email: "owner@example.com",
      role: "owner"
    }

    test "valid attributes" do
      changeset = User.changeset(%User{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid email format" do
      attrs = Map.put(@valid_attrs, :email, "not-an-email")
      changeset = User.changeset(%User{}, attrs)
      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).email
    end

    test "invalid role" do
      attrs = Map.put(@valid_attrs, :role, "invalid")
      changeset = User.changeset(%User{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end
  end
end
