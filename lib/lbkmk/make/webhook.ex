defmodule Lbkmk.Make.Webhook do
  @moduledoc """
  Behaviour for dispatching webhooks to Make.com scenarios.
  """

  @doc """
  Dispatches a payload to a Make webhook URL.

  ## Parameters

    - action: the action name (e.g. "post_xero_invoice")
    - payload: the data to send
  """
  @callback dispatch(String.t(), map()) :: {:ok, term()} | {:error, term()}
end
