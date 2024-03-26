defmodule TwitchAPI do
  @moduledoc """
  Twitch API.

  You can make requests to Twitch API endpoints.

  ## Examples

  ```elixir
    client_id = "asdsdksdl93roi39"
    access_token = "09wriujr329jd023920dk203kd0932d"

    auth = TwitchAPI.Auth.new(client_id, access_token)

    case TwitchAPI.get(auth, "/users") do
      {:ok, %{body: users}} ->
        IO.inspect(users, label: "Successful response body")

      {:error, resp} ->
        IO.inspect(resp, label: "We got an error")
    end
  ```
  """

  alias TwitchAPI.Auth

  require Logger

  @type body_params :: map() | keyword()

  @base_url "https://api.twitch.tv/helix"

  @doc """
  Build a base `t:Req.Request.t/0` for Twitch API requests.

  You can pass either this or a `t:TwitchAPI.Auth.t/0` struct to the
  request functions.

  NOTE: You probably only want to use this directly if you want to do something
  different than the default.
  """
  @spec client(Auth.t()) :: Req.Request.t()
  def client(%Auth{} = auth) do
    headers = %{"client-id" => auth.client_id}
    auth = auth.access_token && {:bearer, auth.access_token}
    Req.new(base_url: @base_url, headers: headers, auth: auth)
  end

  # Metaprogramming to generate all the request method functions.
  # Look, I'm one person and have a lot to do, okay?
  # If you don't like it, go use Gleam or something. ᕕ( ᐛ )ᕗ
  #                    ,-.-.
  #                    `. ,'
  #                      `

  request_methods = [:get, :post, :put, :patch, :delete, :head]

  for method <- request_methods do
    method_upcase = to_string(method) |> String.upcase()
    method! = :"#{method}!"

    @doc """
    Make a Twitch API #{method_upcase} request.
    Returns `:ok` or `:error` tuples.
    """
    @spec unquote(method)(
            auth_or_client :: Auth.t() | Req.Request.t(),
            url :: String.t(),
            opts :: keyword()
          ) ::
            {:ok, Req.Response.t()} | {:error, term()}
    def unquote(method)(auth_or_client, url, opts \\ [])

    def unquote(method)(%Auth{} = auth, url, opts) do
      unquote(method)(client(auth), url, opts)
    end

    def unquote(method)(%Req.Request{} = client, url, opts) do
      {success_code, opts} = Keyword.pop(opts, :success, 200)

      client
      |> Req.unquote(method)([{:url, url} | opts])
      |> handle_response(success_code)
    end

    @doc """
    Make a Twitch API #{method_upcase} request.
    Raises on error or unexpected HTTP status.
    """
    @spec unquote(method!)(
            auth_or_client :: Auth.t() | Req.Request.t(),
            url :: String.t(),
            opts :: keyword()
          ) :: Req.Response.t()
    def unquote(method!)(auth_or_client, url, opts \\ [])

    def unquote(method!)(%Auth{} = auth, url, opts) do
      unquote(method!)(client(auth), url, opts)
    end

    def unquote(method!)(%Req.Request{} = client, url, opts) do
      {success_code, opts} = Keyword.pop(opts, :success, 200)

      client
      |> Req.unquote(method!)([{:url, url} | opts])
      |> handle_response!(success_code)
    end
  end

  @spec handle_response(
          {:ok, Req.Response.t()} | {:error, Req.Response.t() | term()},
          pos_integer()
        ) ::
          {:ok, Req.Response.t()} | {:error, term()}
  defp handle_response(resp, expected_status) do
    case resp do
      {:ok, %{status: ^expected_status} = resp} ->
        Logger.debug("[TwitchAPI] success #{expected_status}")
        {:ok, resp}

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

  @spec handle_response!(Req.Response.t(), pos_integer()) :: Req.Response.t()
  defp handle_response!(resp, expected_status) do
    case resp do
      %{status: ^expected_status} = resp ->
        Logger.debug("[TwitchAPI] success #{expected_status}")
        resp

      %{status: 429, headers: %{"ratelimit-reset" => resets_at}} ->
        raise "rate limited: resets at #{resets_at}"

      %{status: status} ->
        raise "unexpected status #{status}, expected #{expected_status}"
    end
  end
end
