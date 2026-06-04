defmodule Lbkmk.Ingest do
  @moduledoc """
  Context for accepting normalized events from Make, deduplicating,
  persisting, and routing to the lifecycle.
  """

  alias Lbkmk.Ingest.SaleEvent

  @doc """
  Upserts a sale event from an external source. Idempotent on
  `(tenant_id, channel, external_event_id)`.
  """
  @spec upsert_event(map()) :: {:ok, SaleEvent.t()} | {:error, Ecto.Changeset.t()}
  def upsert_event(_attrs) do
    {:error, :not_implemented}
  end

  @doc """
  Resolves line items within a sale event against known channel SKUs.
  """
  @spec resolve_lines(SaleEvent.t()) :: {:ok, SaleEvent.t()} | {:error, atom()}
  def resolve_lines(_sale_event) do
    {:error, :not_implemented}
  end
end
