defmodule TwitchAPI.Auth do
  @moduledoc """
  Auth struct.
  """

  @type t :: %__MODULE__{client_id: String.t(), access_token: String.t() | nil}

  @derive {Inspect, only: [:client_id]}

  @enforce_keys [:client_id]

  defstruct [:client_id, :access_token]

  @doc """
  Make a new Auth struct.
  """
  @spec new(client_id :: String.t(), access_token :: String.t() | nil) :: t()
  def new(client_id, access_token \\ nil) do
    %__MODULE__{client_id: client_id, access_token: access_token}
  end
end