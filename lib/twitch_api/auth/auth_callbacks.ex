defmodule TwitchAPI.AuthCallbacks do
  @moduledoc """
  Behaviour defined for `TwitchAPI.AuthStore` callback options.
  """

  alias TwitchAPI.Auth

  @typedoc """
  The `name` argument is the name used to register the auth store in the 
  `Registry`, and is useful for distinguishing between different auth stores
  if you have many.
  """
  @type name :: term()

  @doc """
  This function is called after the `TwitchAPI.AuthStore.init/2` function is
  called, and before the token is validated (and attempted to refresh if not
  valid).
  """
  @callback load(name(), Auth.t()) :: Auth.t()

  @doc """
  This function is called whenever a `t:TwitchAPI.Auth.t/0` is added to the
  store and every time a token is refreshed.
  """
  @callback put(name(), Auth.t()) :: Auth.t()

  @doc """
  This function is called whenever the `TwitchAPI.AuthStore.terminate/2`
  function is called. It is useful for any clean-up needed.
  """
  @callback terminate(name(), Auth.t()) :: Auth.t()
end
