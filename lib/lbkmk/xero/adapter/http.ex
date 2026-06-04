defmodule Lbkmk.Xero.Adapter.HTTP do
  @moduledoc """
  HTTP client implementation of the Xero adapter.
  Empty for now — will be wired once the OAuth flow is implemented.
  """
  @behaviour Lbkmk.Xero.Adapter

  @impl true
  def post_bank_transaction(_payload) do
    {:error, :not_implemented}
  end

  @impl true
  def get_bank_transaction(_xero_id) do
    {:error, :not_implemented}
  end

  @impl true
  def list_items do
    {:error, :not_implemented}
  end
end
