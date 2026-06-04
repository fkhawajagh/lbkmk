defmodule Lbkmk.Accounts.User do
  @moduledoc """
  Schema for a user account.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :tenant_id, Ecto.UUID
    field :email, :string
    field :role, :string, default: "owner"

    timestamps(type: :utc_datetime_usec)
  end

  @roles ~w(owner admin)

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:tenant_id, :email, :role])
    |> validate_required([:tenant_id, :email, :role])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:tenant_id, :email])
  end
end
