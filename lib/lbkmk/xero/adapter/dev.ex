defmodule Lbkmk.Xero.Adapter.Dev do
  @moduledoc """
  Development stub for the Xero adapter. Logs instead of calling Xero.
  """
  @behaviour Lbkmk.Xero.Adapter

  require Logger

  @impl true
  def post_bank_transaction(payload) do
    Logger.info("[Xero.Adapter.Dev] post_bank_transaction: #{inspect(payload)}")
    {:ok, %{"BankTransactionID" => "dev-bt-" <> Ecto.UUID.generate()}}
  end

  @impl true
  def get_bank_transaction(xero_id) do
    Logger.info("[Xero.Adapter.Dev] get_bank_transaction: #{xero_id}")
    {:ok, %{"BankTransactionID" => xero_id}}
  end

  @impl true
  def list_items do
    Logger.info("[Xero.Adapter.Dev] list_items")
    {:ok, [%{"ItemCode" => "DEV-ITEM-1", "Name" => "Development Item"}]}
  end
end
