defmodule TwitchAPI.Auth do
  @moduledoc """
  Twitch API Auth (and struct).

  Functions for managing your auth and tokens.

  ## Notes

   * `Implicit` grant flow gives user access tokens that expire in `14124`
     seconds (~4 hours).

   * `Client Credentials` grant flow gives app access tokens that expire
     in `5011271` seconds (~58 days).

   * `Authorization Code` Grant flow gives user access tokens that expires
     in `14124` seconds (~4 hours).

  """

  @base_url "https://id.twitch.tv"

  @type t :: %__MODULE__{
          client_id: String.t(),
          client_secret: String.t() | nil,
          access_token: String.t() | nil,
          refresh_token: String.t() | nil,
          expires_at: DateTime.t() | nil
        }

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
  @spec new(client_id :: String.t(), client_secret :: String.t()) :: t()
  def new(client_id, client_secret) when is_binary(client_id) and is_binary(client_secret) do
    %__MODULE__{client_id: client_id, client_secret: client_secret}
  end

  @doc """
  Make a new `Auth` struct with a `client_id`, `client_secret`, and `access_token`.

  ## Example

      iex> Auth.new("some-client-id", "secretssss", "sometokenabc123")
      %Auth{client_id: "some-client-id", client_secret: "secretssss", access_token: "sometokenabc123"}

  """
  @spec new(client_id :: String.t(), client_secret :: String.t(), access_token :: String.t()) ::
          t()
  def new(client_id, client_secret, access_token)
      when is_binary(client_id) and is_binary(client_secret) and is_binary(access_token) do
    %__MODULE__{client_id: client_id, client_secret: client_secret, access_token: access_token}
  end

  @doc """
  Add a `client_secret` to the `Auth` struct.

  ## Example

      iex> auth = Auth.new("some-client-id")
      iex> Auth.put_client_secret(auth, "secretssss")
      %Auth{client_id: "some-client-id", client_secret: "secretssss"}

  """
  @spec put_client_secret(t(), client_secret :: String.t()) :: t()
  def put_client_secret(%__MODULE__{} = auth, client_secret) when is_binary(client_secret) do
    struct(auth, %{client_secret: client_secret})
  end

  @doc """
  Add an `access_token` to the `Auth` struct.

  ## Example

      iex> auth = Auth.new("some-client-id")
      iex> Auth.put_access_token(auth, "abc123")
      %Auth{client_id: "some-client-id", access_token: "abc123"}

  """
  @spec put_access_token(t(), access_token :: String.t()) :: t()
  def put_access_token(%__MODULE__{} = auth, access_token) when is_binary(access_token) do
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

  @doc """
  Refresh an access token.

  https://dev.twitch.tv/docs/authentication/refresh-tokens

  If the request succeeds, the response contains the new access token, refresh
  token, and scopes associated with the new grant. Because refresh tokens may
  change, your app should safely store the new refresh token to use the next time.

      {
        "access_token": "1ssjqsqfy6bads1ws7m03gras79zfr",
        "refresh_token": "eyJfMzUtNDU0OC4MWYwLTQ5MDY5ODY4NGNlMSJ9%asdfasdf=",
        "scope": [
          "channel:read:subscriptions",
          "channel:manage:polls"
        ],
        "token_type": "bearer"
      }

  The following example shows what the response looks like if the request fails.

      {
        "error": "Bad Request",
        "status": 400,
        "message": "Invalid refresh token"
      }

  """
  @spec token_refresh(t()) :: {:ok, Req.Response.t()} | {:error, term()}
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

  https://dev.twitch.tv/docs/authentication/revoke-tokens

  If the revocation succeeds, the request returns HTTP status code 200 OK (with no body).

  If the revocation fails, the request returns one of the following HTTP status codes:

   * 400 Bad Request if the client ID is valid but the access token is not.

      {
        "status": 400,
        "message": "Invalid token"
      }

   * 404 Not Found if the client ID is not valid.

      {
        "status": 404,
        "message": "client does not exist"
      }

  """
  @spec token_revoke(t()) :: {:ok, Req.Response.t()} | {:error, term()}
  def token_revoke(%__MODULE__{} = auth) do
    params = [client_id: auth.client_id, token: auth.access_token]
    Req.post(client(), url: "/oauth2/revoke", form: params)
  end

  @doc """
  Get an access token with an authorization code.

  https://dev.twitch.tv/docs/authentication/getting-tokens-oauth/#authorization-code-grant-flow

  If the request succeeds, it returns an access token and refresh token.

      {
        "access_token": "rfx2uswqe8l4g1mkagrvg5tv0ks3",
        "expires_in": 14124,
        "refresh_token": "5b93chm6hdve3mycz05zfzatkfdenfspp1h1ar2xxdalen01",
        "scope": [
          "channel:moderate",
          "chat:edit",
          "chat:read"
        ],
        "token_type": "bearer"
      }

  """
  @spec token_get_from_code(t(), code :: String.t(), redirect_url :: String.t()) ::
          {:ok, Req.Response.t()} | {:error, term()}
  def token_get_from_code(%__MODULE__{} = auth, code, redirect_url) do
    params = [
      client_id: auth.client_id,
      client_secret: auth.client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_url
    ]

    Req.post(client(), url: "/oauth2/token", form: params)
  end

  @doc """
  Validate an access token.

  https://dev.twitch.tv/docs/authentication/validate-tokens/#how-to-validate-a-token

  If the token is valid, the request returns HTTP status code 200 and the
  response’s body contains the following JSON object:

      {
        "client_id": "wbmytr93xzw8zbg0p1izqyzzc5mbiz",
        "login": "twitchdev",
        "scopes": [
          "channel:read:subscriptions"
        ],
        "user_id": "141981764",
        "expires_in": 5520838
      }

  If the token is not valid, the request returns HTTP status code 401 and the
  response’s body contains the following JSON object:

      {
        "status": 401,
        "message": "invalid access token"
      }

  """
  @spec token_validate(t()) :: {:ok, Req.Response.t()} | {:error, term()}
  def token_validate(%__MODULE__{} = auth) do
    headers = %{
      "authorization" => "OAuth #{auth.access_token}"
    }

    Req.get(@base_url <> "/oauth2/validate", headers: headers)
  end

  @doc """
  Attach a refresh step to requests.
  """
  @spec token_refresh_step({Req.Request.t(), Req.Response.t()}) ::
          {Req.Request.t(), Req.Response.t()}
  def token_refresh_step({request, %{status: 401} = response}) do
    auth = Req.Request.get_private(request, :twitch_auth)
    attempted? = Req.Request.get_private(request, :refresh_attempted?, false)

    cond do
      !auth ->
        {request, response}

      !auth.refresh_token ->
        {request, response}

      attempted? ->
        {request, response}

      true ->
        case token_refresh(auth) do
          {:ok, %{status: 200, body: auth_attrs}} ->
            auth = merge_string_params(auth, auth_attrs)

            {request, response_or_exception} =
              request
              |> Req.Request.put_private(:twitch_auth, auth)
              |> Req.Request.put_private(:refresh_attempted?, true)
              |> Req.Request.merge_options(auth: {:bearer, auth.access_token})
              |> Req.Request.run_request()

            {Req.Request.halt(request), response_or_exception}

          {_ok_error, _resp} ->
            {request, response}
        end
    end
  end

  def refresh_step({request, response}) do
    {request, response}
  end

  # ----------------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------------

  @spec client() :: Req.Request.t()
  defp client do
    Req.new(base_url: @base_url)
  end

  @spec expires_in_to_datetime(nil | pos_integer()) :: nil | DateTime.t()
  defp expires_in_to_datetime(nil), do: nil

  defp expires_in_to_datetime(expires_in) when is_integer(expires_in) do
    DateTime.utc_now() |> DateTime.add(expires_in, :seconds)
  end
end
