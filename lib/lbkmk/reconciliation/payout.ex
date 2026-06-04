defmodule Lbkmk.Reconciliation.Payout do
  @moduledoc """
  Schema for a bank deposit from a payment processor.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "payouts" do
    field :tenant_id, Ecto.UUID
    field :processor, :string
    field :processor_payout_id, :string
    field :gross, :decimal
    field :fee, :decimal
    field :net, :decimal
    field :paid_on, :date
    field :state, :string, default: "received"

    timestamps(type: :utc_datetime_usec)
  end

  @processors ~w(stripe square)
  @states ~w(received reconciled drift_flagged)

  @doc false
  def changeset(payout, attrs) do
    payout
    |> cast(attrs, [
      :tenant_id,
      :processor,
      :processor_payout_id,
      :gross,
      :fee,
      :net,
      :paid_on,
      :state
    ])
    |> validate_required([
      :tenant_id,
      :processor,
      :processor_payout_id,
      :gross,
      :net,
      :paid_on,
      :state
    ])
    |> validate_inclusion(:processor, @processors)
    |> validate_inclusion(:state, @states)
    |> unique_constraint([:tenant_id, :processor, :processor_payout_id])
  end
end
