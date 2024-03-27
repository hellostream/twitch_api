defmodule TwitchAPI.Auth do
  @moduledoc """
  Auth struct.
  """

  @type t :: %__MODULE__{
          access_token: String.t() | nil,
          client_id: String.t(),
          client_secret: String.t() | nil,
          refresh_token: String.t() | nil
        }

  @base_url "https://id.twitch.tv"

  @derive {Inspect, only: [:client_id]}
  @enforce_keys [:client_id]
  defstruct [:access_token, :client_id, :client_secret, :refresh_token]

  @doc """
  Make a new Auth struct.
  """
  @spec new(client_id :: String.t(), access_token :: String.t() | nil) :: t()
  def new(client_id, access_token \\ nil) do
    %__MODULE__{client_id: client_id, access_token: access_token}
  end

  @doc """
  Refresh an access token.
  """
  @spec token_refresh(Auth.t()) :: {:ok, Req.Response.t()} | {:error, term()}
  def token_refresh(%__MODULE__{} = auth) do
    params = [
      grant_type: "refresh_token",
      client_id: auth.client_id,
      client_secret: auth.client_secret,
      refresh_token: auth.refresh_token
    ]

    Req.post(client(), url: "/oauth2/token", form: params)
  end

  @doc """
  Revoke an access token.
  """
  @spec token_revoke(Auth.t()) :: {:ok, Req.Response.t()} | {:error, term()}
  def token_revoke(%__MODULE__{} = auth) do
    params = [client_id: auth.client_id, token: auth.access_token]
    Req.post(client(), url: "/oauth2/revoke", form: params)
  end

  # ----------------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------------

  @spec client() :: Req.Request.t()
  defp client do
    Req.Request.new(base_url: @base_url)
  end
end
