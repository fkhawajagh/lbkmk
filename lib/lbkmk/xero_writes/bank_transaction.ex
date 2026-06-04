defmodule Lbkmk.XeroWrites.BankTransaction do
  @moduledoc """
  Schema tracking a Xero BankTransaction created from an approved sale event.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "xero_bank_transactions" do
    field :tenant_id, Ecto.UUID
    field :xero_bank_transaction_id, :string
    field :xero_reference, :string
    field :posted_at, :utc_datetime_usec

    belongs_to :sale_event, Lbkmk.Ingest.SaleEvent, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(bank_transaction, attrs) do
    bank_transaction
    |> cast(attrs, [
      :tenant_id,
      :sale_event_id,
      :xero_bank_transaction_id,
      :xero_reference,
      :posted_at
    ])
    |> validate_required([
      :tenant_id,
      :sale_event_id,
      :xero_bank_transaction_id,
      :xero_reference,
      :posted_at
    ])
    |> unique_constraint([:tenant_id, :xero_bank_transaction_id])
    |> unique_constraint([:tenant_id, :sale_event_id])
    |> foreign_key_constraint(:sale_event_id)
  end
end
