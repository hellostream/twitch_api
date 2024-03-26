defmodule TwitchAPI do
  @moduledoc """
  Twitch API.
  """

  alias TwitchAPI.Auth

  require Logger

  @type body_params :: map() | keyword()

  @type body_resp :: String.t() | map() | nil

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
  Make a Twitch API GET request.

  ## Examples

      iex> get(auth, "/users", params)
      {:ok, %{"data" => []}}

  """
  @spec get(Auth.t(), String.t(), keyword()) :: {:ok, body_resp()} | {:error, term()}
  def get(%Auth{} = auth, url, opts \\ []) do
    {success_code, opts} = Keyword.pop(opts, :success, 200)

    auth
    |> client()
    |> Req.get([{:url, url} | opts])
    |> handle_response(success_code)
  end

  @doc """
  Make a Twitch API POST request with JSON body.
  """
  @spec post(Auth.t(), String.t(), keyword()) :: {:ok, body_resp()} | {:error, term()}
  def post(%Auth{} = auth, url, opts \\ []) do
    {success_code, opts} = Keyword.pop(opts, :success, 200)

    auth
    |> client()
    |> Req.post([{:url, url} | opts])
    |> handle_response(success_code)
  end

  @doc """
  Make a Twitch API PATCH request with JSON body.
  """
  @spec patch(Auth.t(), String.t(), keyword()) :: {:ok, body_resp()} | {:error, term()}
  def patch(%Auth{} = auth, url, opts \\ []) do
    {success_code, opts} = Keyword.pop(opts, :success, 200)

    auth
    |> client()
    |> Req.patch([{:url, url} | opts])
    |> handle_response(success_code)
  end

  @doc """
  Handle the result of a request to Twitch.
  """
  @spec handle_response({:ok, Req.Response.t()} | {:error, term()}, pos_integer()) ::
          {:ok, body_resp()} | {:error, term()}
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
        ) :: {:ok, body_resp()} | {:error, term()}
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
  @spec create_eventsub_subscription(
          Auth.t(),
          type :: String.t(),
          version :: String.t(),
          transport :: map(),
          condition :: map()
        ) :: {:ok, body_resp()} | {:error, term()}
  def create_eventsub_subscription(auth, type, version, transport, condition) do
    params = %{
      "type" => type,
      "version" => version,
      "condition" => condition,
      "transport" => transport
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
  @spec list_eventsub_subscriptions(Auth.t(), body_params()) ::
          {:ok, body_resp()} | {:error, term()}
  def list_eventsub_subscriptions(auth, params \\ %{}) do
    client(auth)
    |> Req.get(url: "/eventsub/subscriptions", json: params)
    |> handle_response()
  end
end
