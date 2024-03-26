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

  @doc """
  Revoke an access token.
  """
  @spec revoke_token!(Auth.t()) :: Req.Response.t()
  def revoke_token!(%__MODULE__{} = auth) do
    params = [client_id: auth.client_id, token: auth.access_token]
    Req.post!("https://id.twitch.tv/oauth2/revoke", form: params)
  end
end
