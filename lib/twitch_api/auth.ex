defmodule TwitchAPI.Auth do
  @moduledoc """
  Twitch API Auth (and struct).

  Functions for managing your auth and tokens.

  See: https://dev.twitch.tv/docs/authentication/getting-tokens-oauth

  ## Notes

   * `Implicit` grant flow gives user access tokens. Expiry: I don't know yet.

   * `Client Credentials` grant flow gives app access tokens that expire
     in `5011271` seconds (~58 days).

   * `Authorization Code` grant flow gives user access tokens that expires
     in `14124` seconds (~4 hours).

   * `Device Code` grant flow gives a user access token that expires in
     `14820` seconds (~4 hours).

  """

  require Logger

  @type t :: %__MODULE__{
          client_id: String.t(),
          client_secret: String.t() | nil,
          access_token: String.t() | nil,
          refresh_token: String.t() | nil,
          expires_at: DateTime.t() | nil
        }

  @derive Jason.Encoder
  @derive {Inspect, only: [:client_id, :expires_at]}
  @enforce_keys [:client_id]
  defstruct [:client_id, :client_secret, :access_token, :refresh_token, :expires_at]

  @doc """
  Make a new `Auth` struct with a `client_id`.

  ## Example

      iex> Auth.new("some-client-id")
      %Auth{client_id: "some-client-id"}

  """
  @spec new(client_id :: String.t()) :: t()
  def new(client_id) when is_binary(client_id) do
    %__MODULE__{client_id: client_id}
  end

  @doc """
  Make a new `Auth` struct with a `client_id` and `client_secret`.

  ## Example

      iex> Auth.new("some-client-id", "secretssss")
      %Auth{client_id: "some-client-id", client_secret: "secretssss"}

  """
  @spec new(client_id :: String.t(), client_secret :: String.t() | nil) :: t()
  def new(client_id, client_secret) when is_binary(client_id) do
    %__MODULE__{client_id: client_id, client_secret: client_secret}
  end

  @doc """
  Make a new `Auth` struct with a `client_id`, `client_secret`, and `access_token`.

  ## Example

      iex> Auth.new("some-client-id", "secretssss", "sometokenabc123")
      %Auth{client_id: "some-client-id", client_secret: "secretssss", access_token: "sometokenabc123"}

  """
  @spec new(
          client_id :: String.t(),
          client_secret :: String.t() | nil,
          access_token :: String.t() | nil
        ) ::
          t()
  def new(client_id, client_secret, access_token) when is_binary(client_id) do
    %__MODULE__{client_id: client_id, client_secret: client_secret, access_token: access_token}
  end

  @doc """
  Make a new `Auth` struct with a `client_id`, `client_secret`, `access_token`, and `refresh_token`.

  ## Example

      iex> Auth.new("some-client-id", "secretssss", "sometokenabc123", "somerefreshabc123")
      %Auth{
        client_id: "some-client-id",
        client_secret: "secretssss",
        access_token: "sometokenabc123",
        refresh_token: "somerefreshabc123"
      }

  """
  @spec new(
          client_id :: String.t(),
          client_secret :: String.t() | nil,
          access_token :: String.t() | nil,
          refresh_token :: String.t() | nil
        ) ::
          t()
  def new(client_id, client_secret, access_token, refresh_token) when is_binary(client_id) do
    %__MODULE__{
      client_id: client_id,
      client_secret: client_secret,
      access_token: access_token,
      refresh_token: refresh_token
    }
  end

  @doc """
  Add a `client_secret` to the `Auth` struct.

  ## Example

      iex> auth = Auth.new("some-client-id")
      iex> Auth.put_client_secret(auth, "secretssss")
      %Auth{client_id: "some-client-id", client_secret: "secretssss"}

  """
  @spec put_client_secret(t(), client_secret :: String.t() | nil) :: t()
  def put_client_secret(%__MODULE__{} = auth, client_secret) do
    struct(auth, %{client_secret: client_secret})
  end

  @doc """
  Add an `access_token` to the `Auth` struct.

  ## Example

      iex> auth = Auth.new("some-client-id")
      iex> Auth.put_access_token(auth, "abc123")
      %Auth{client_id: "some-client-id", access_token: "abc123"}

  """
  @spec put_access_token(t(), access_token :: String.t() | nil) :: t()
  def put_access_token(%__MODULE__{} = auth, access_token) do
    struct(auth, %{access_token: access_token})
  end

  @doc """
  Merge string params into `Auth` struct.

  ## Example

      iex> auth = Auth.new("some-client-id")
      iex> params = %{"access_token" => "abc123", "refresh_token" => "def456"}
      iex> Auth.merge_string_params(auth, params)
      %Auth{
        client_id: "some-client-id",
        access_token: "abc123",
        refresh_token: "def456"
      }

  """
  @spec merge_string_params(t(), params :: %{String.t() => term()}) :: t()
  def merge_string_params(%__MODULE__{} = auth, %{} = params) do
    struct(auth, %{
      access_token: params["access_token"],
      expires_at: expires_in_to_datetime(params["expires_in"]),
      refresh_token: params["refresh_token"]
    })
  end

  @spec expires_in_to_datetime(nil | pos_integer()) :: nil | DateTime.t()
  defp expires_in_to_datetime(nil), do: nil

  defp expires_in_to_datetime(expires_in) when is_integer(expires_in) do
    DateTime.utc_now() |> DateTime.add(expires_in, :second)
  end
end
