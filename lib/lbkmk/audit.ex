defmodule Lbkmk.Audit do
  @moduledoc """
  Context for append-only audit logging and forensic queries.
  """

  alias Lbkmk.Audit.LogEntry

  @doc """
  Records an audit log entry.

  ## Parameters

    - actor_type: "system" or "user"
    - actor_id: identifier of the actor (nil for system)
    - action: the action being recorded
    - subject: tuple of {subject_type, subject_id}
    - metadata: optional map of additional context
  """
  @spec record(String.t(), String.t() | nil, {String.t(), String.t()}, map()) ::
          {:ok, LogEntry.t()} | {:error, Ecto.Changeset.t()}
  def record(_actor_type, _actor_id, _subject, _metadata \\ %{}) do
    {:error, :not_implemented}
  end

  @doc """
  Returns the audit timeline for a given subject.
  """
  @spec timeline_for({String.t(), String.t()}) :: list(LogEntry.t())
  def timeline_for(_subject) do
    []
  end
end
