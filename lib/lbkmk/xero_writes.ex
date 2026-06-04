defmodule Lbkmk.XeroWrites do
  @moduledoc """
  Context for dispatching outbound actions to Make's webhook
  and handling the result.
  """

  alias Lbkmk.Ingest.SaleEvent

  @doc """
  Dispatches a sale event to Make for Xero BankTransaction creation.
  """
  @spec dispatch(SaleEvent.t()) :: {:ok, term()} | {:error, atom()}
  def dispatch(_sale_event) do
    {:error, :not_implemented}
  end

  @doc """
  Handles the result payload from Make after a Xero write attempt.
  """
  @spec handle_result(map()) :: {:ok, term()} | {:error, atom()}
  def handle_result(_payload) do
    {:error, :not_implemented}
  end
end
