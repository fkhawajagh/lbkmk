defmodule Lbkmk.Xero.Adapter do
  @moduledoc """
  Behaviour for Xero API interactions.
  """

  @doc """
  Posts a RECEIVE BankTransaction to Xero.
  """
  @callback post_bank_transaction(map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Fetches an existing BankTransaction by its Xero ID.
  """
  @callback get_bank_transaction(String.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Lists all tracked items from Xero.
  """
  @callback list_items() :: {:ok, list(map())} | {:error, term()}
end
