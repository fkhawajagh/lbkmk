defmodule Lbkmk.Reconciliation do
  @moduledoc """
  Context for matching payment-to-sale events, checking line totals,
  applying state transitions, and running the matching ladder.
  """

  alias Lbkmk.Ingest.SaleEvent

  @doc """
  Attempts to correlate a sale event with its payment-side counterpart.
  """
  @spec try_correlate(SaleEvent.t()) :: {:ok, term()} | {:error, atom()}
  def try_correlate(_sale_event) do
    {:error, :not_implemented}
  end

  @doc """
  Approves a sale event for posting to Xero.
  """
  @spec approve(SaleEvent.t(), String.t()) :: {:ok, SaleEvent.t()} | {:error, atom()}
  def approve(_sale_event, _user_id) do
    {:error, :not_implemented}
  end

  @doc """
  Rejects a sale event (e.g. test transaction, duplicate).
  """
  @spec reject(SaleEvent.t(), String.t()) :: {:ok, SaleEvent.t()} | {:error, atom()}
  def reject(_sale_event, _user_id) do
    {:error, :not_implemented}
  end

  @doc """
  Runs the daily payout sweep to compare approved invoices against
  processor payouts.
  """
  @spec sweep_payouts() :: {:ok, term()} | {:error, atom()}
  def sweep_payouts do
    {:error, :not_implemented}
  end
end
