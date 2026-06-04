defmodule Lbkmk.Xero.TokenStore do
  @moduledoc """
  Behaviour for Xero OAuth token storage and refresh.
  """

  @doc """
  Returns the current access token, refreshing if necessary.
  """
  @callback get_access_token() :: {:ok, String.t()} | {:error, term()}

  @doc """
  Forces a token refresh using the stored refresh token.
  """
  @callback refresh() :: {:ok, map()} | {:error, term()}

  @doc """
  Stores a new access token and refresh token.
  """
  @callback store(String.t(), String.t()) :: :ok | {:error, term()}
end
