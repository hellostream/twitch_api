defmodule TwitchAPI do
  @moduledoc """
  Twitch API.
  """

  alias TwitchAPI.Auth

  require Logger

  @type body_params :: map() | keyword()

  @type response :: {:ok, map() | String.t() | nil} | {:error, term()}

  @base_url "https://api.twitch.tv/helix"

  @doc """
  Build a base `t:Req.Request.t/0` for Twitch API requests.
  """
  @spec client(Auth.t()) :: Req.Request.t()
  def client(%Auth{} = auth) do
    headers = %{"client-id" => auth.client_id}
    auth = auth.access_token && {:bearer, auth.access_token}
    Req.new(base_url: @base_url, headers: headers, auth: auth)
  end

  @doc """
  Handle the result of a request to Twitch.
  """
  @spec handle_response({:ok, Req.Response.t()} | {:error, term()}, pos_integer()) :: response()
  def handle_response(resp, expected_status \\ 200) do
    case resp do
      {:ok, %{status: ^expected_status, headers: _headers, body: body}} ->
        Logger.debug("[TwitchAPI] success:\n#{inspect(body)}")
        {:ok, body}

      {:ok, %{status: 429, headers: %{"ratelimit-reset" => resets_at}}} ->
        Logger.warning("[TwitchAPI] rate-limited; resets at #{resets_at}")
        {:error, resp}

      {:ok, %{status: _status} = resp} ->
        Logger.error("[TwitchAPI] unexpected response: #{inspect(resp)}")
        {:error, resp}

      {:error, error} ->
        Logger.error("[TwitchAPI] error making request: #{inspect(error)}")
        {:error, error}
    end
  end

  # ----------------------------------------------------------------------------
  # Auth/Tokens
  # ----------------------------------------------------------------------------

  @doc """
  Revoke an access token.
  """
  @spec revoke_token!(Auth.t()) :: Req.Response.t()
  def revoke_token!(auth) do
    params = [client_id: auth.client_id, token: auth.token]
    Req.post!("https://id.twitch.tv/oauth2/revoke", form: params)
  end

  # ----------------------------------------------------------------------------
  # Custom Rewards
  # ----------------------------------------------------------------------------

  @doc """
  Update Custom Reward
  https://dev.twitch.tv/docs/api/reference/#update-custom-reward

  ## Authorization

   * Requires user access token with `channel:manage:redemptions` scope.

  """
  @spec update_custom_reward(
          Auth.t(),
          broadcaster_id :: String.t(),
          reward_id :: String.t(),
          body_params()
        ) :: response()
  def update_custom_reward(auth, broadcaster_id, reward_id, fields) do
    query = [broadcaster_id: broadcaster_id, id: reward_id]

    client(auth)
    |> Req.patch(url: "/channel_points/custom_rewards", query: query, json: fields)
    |> handle_response()
  end

  # ----------------------------------------------------------------------------
  # EventSub Subscriptions
  # ----------------------------------------------------------------------------

  @doc """
  Create an eventsub subscription using.
  https://dev.twitch.tv/docs/api/reference/#create-eventsub-subscription

  ## Authorization

   * If you use webhooks to receive events, the request must specify an app
     access token. The request will fail if you use a user access token.
   * If you use WebSockets to receive events, the request must specify a user
     access token. The request will fail if you use an app access token. The
     token may include any scopes.

  """
  @spec create_eventsub_websocket_subscription(
          Auth.t(),
          session_id :: String.t(),
          type :: String.t(),
          version :: String.t(),
          condition :: map()
        ) :: response()
  def create_eventsub_websocket_subscription(auth, session_id, type, version, condition) do
    params = %{
      "type" => type,
      "version" => version,
      "condition" => condition,
      "transport" => %{
        "method" => "websocket",
        "session_id" => session_id
      }
    }

    client(auth)
    |> Req.post(url: "/eventsub/subscriptions", json: params)
    |> handle_response(202)
  end

  @doc """
  List EventSub Subscriptions.
  https://dev.twitch.tv/docs/api/reference/#get-eventsub-subscriptions

  ## Authorization

   * If you use webhooks to receive events, the request must specify an app
     access token. The request will fail if you use a user access token.
   * If you use WebSockets to receive events, the request must specify a user
     access token. The request will fail if you use an app access token. The
     token may include any scopes.

  """
  @spec list_eventsub_subscriptions(Auth.t(), body_params()) :: response()
  def list_eventsub_subscriptions(auth, params \\ %{}) do
    client(auth)
    |> Req.get(url: "/eventsub/subscriptions", json: params)
    |> handle_response()
  end
end
