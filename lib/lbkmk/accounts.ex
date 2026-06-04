defmodule Lbkmk.Accounts do
  @moduledoc """
  Context for user account management.
  """

  alias Lbkmk.Accounts.User

  @doc """
  Fetches a user by their ID.
  """
  @spec get_user(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_user(_id) do
    {:error, :not_implemented}
  end

  @doc """
  Registers a new user.
  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(_attrs) do
    {:error, :not_implemented}
  end
end
