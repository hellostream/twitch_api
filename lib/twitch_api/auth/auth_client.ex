defmodule TwitchAPI.AuthClient do
  @moduledoc """
  Auth client for Twitch.
  """

  alias TwitchAPI.Auth
  alias TwitchAPI.AuthStore

  require Logger

  @base_url "https://id.twitch.tv"

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
  @spec token_refresh(Auth.t()) :: {:ok, Req.Response.t()} | {:error, term()}
  def token_refresh(%Auth{} = auth) do
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
  @spec token_revoke(Auth.t()) :: {:ok, Req.Response.t()} | {:error, term()}
  def token_revoke(%Auth{} = auth) do
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
  @spec token_get_from_code(Auth.t(), code :: String.t(), redirect_url :: String.t()) ::
          {:ok, Req.Response.t()} | {:error, term()}
  def token_get_from_code(%Auth{} = auth, code, redirect_url) do
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
  @spec token_validate(Auth.t()) :: {:ok, Req.Response.t()} | {:error, term()}
  def token_validate(%Auth{} = auth) do
    headers = %{
      "authorization" => "OAuth #{auth.access_token}"
    }

    Req.get(@base_url <> "/oauth2/validate", headers: headers)
  end

  @doc """
  A response step (`Req.Step`) for refreshing tokens and re-attempting a request
  when authentication fails.

  If the `Auth` struct has a `client_secret` and `refresh_token` and has not
  already been attempted, then we will attempt to refresh the token.

  ## Example

    Req.new(url: "https://api.twitch.com/helix/users")
    |> Req.Request.append_response_steps(token_refresh: &TwitchAPI.Auth.token_refresh_step/1)

  """
  @spec token_refresh_step({Req.Request.t(), Req.Response.t()}) ::
          {Req.Request.t(), Req.Response.t()}
  def token_refresh_step(request_response)

  def token_refresh_step({request, %{status: 401} = response}) do
    Logger.debug("[TwitchAPI] 401 unauthorized #{inspect(response)}")
    auth = Req.Request.get_private(request, :twitch_auth)
    auth_store = Req.Request.get_private(request, :auth_store)
    attempted? = Req.Request.get_private(request, :refresh_attempted?)

    auth =
      case auth_store do
        nil -> auth
        auth_store -> AuthStore.get(auth_store)
      end

    cond do
      !auth ->
        Logger.warning("[TwitchAPI] Auth struct required to refresh access token")
        {request, response}

      !auth.client_secret ->
        Logger.warning("[TwitchAPI] Auth requires :client_secret to refresh access token")
        {request, response}

      !auth.refresh_token ->
        Logger.warning("[TwitchAPI] Auth requires :refresh_token to refresh access token")
        {request, response}

      attempted? ->
        Logger.warning("[TwitchAPI] already attempted to refresh access token")
        {request, response}

      true ->
        case token_refresh(auth) do
          {:ok, %{status: 200, body: auth_attrs}} ->
            Logger.info("[TwitchAPI] refreshed token")
            auth = Auth.merge_string_params(auth, auth_attrs)
            on_refresh = Req.Request.get_option(request, :on_token_refresh)

            auth_store && AuthStore.put(auth_store, auth)

            {request, response_or_exception} =
              request
              |> Req.Request.put_private(:twitch_auth, auth)
              |> Req.Request.put_private(:refresh_attempted?, true)
              |> Req.Request.merge_options(auth: {:bearer, auth.access_token})
              |> Req.Request.run_request()

            if is_function(on_refresh) do
              on_refresh.(auth)
            end

            {Req.Request.halt(request), response_or_exception}

          {_ok_error, resp} ->
            Logger.error("[TwitchAPI] failed to refresh access token")
            Logger.debug(inspect(resp, pretty: true))
            {request, response}
        end
    end
  end

  def token_refresh_step({request, response}) do
    {request, response}
  end

  # ----------------------------------------------------------------------------
  # Private API
  # ----------------------------------------------------------------------------

  @spec client() :: Req.Request.t()
  defp client do
    Req.new(base_url: @base_url)
  end
end
