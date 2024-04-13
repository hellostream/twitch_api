defmodule TwitchAPI.AuthNoop do
  @moduledoc """
  Some functions that no-op.
  """
  @behaviour TwitchAPI.AuthCallbacks

  @impl true
  def load(_name, auth), do: auth

  @impl true
  def put(_name, auth), do: auth

  @impl true
  def terminate(_name, auth), do: auth
end
