defmodule TwitchAPI do
  @moduledoc """
  Twitch API.

  You can make requests to Twitch API endpoints.

  ## Examples

      client_id = "asdsdksdl93roi39"
      access_token = "09wriujr329jd023920dk203kd0932d"

      auth = TwitchAPI.Auth.new(client_id, access_token)

      case TwitchAPI.get(auth, "/users") do
        {:ok, %{body: users}} ->
          IO.inspect(users, label: "Successful response body")

        {:error, resp} ->
          IO.inspect(resp, label: "We got an error")
      end

  """

  alias TwitchAPI.Auth
  alias TwitchAPI.AuthStore

  require Logger

  @base_url "https://api.twitch.tv/helix"

  @doc """
  Build a base `t:Req.Request.t/0` for Twitch API requests.

  You can pass either this or a `t:TwitchAPI.Auth.t/0` struct to the
  request functions.

  NOTE: You probably only want to use this directly if you want to do something
  different than the default.
  """
  @spec client(Auth.t() | AuthStore.name()) :: Req.Request.t()
  def client(%Auth{} = auth) do
    headers = %{"client-id" => auth.client_id}
    auth_opts = auth.access_token && {:bearer, auth.access_token}

    Req.new(base_url: @base_url, headers: headers, auth: auth_opts)
    |> Req.Request.register_options([:on_token_refresh, :on_auth_request])
    |> Req.Request.put_private(:twitch_auth, auth)
    |> Req.Request.put_private(:refresh_attempted?, false)
    |> Req.Request.append_response_steps(refresh: &Auth.token_refresh_step/1)
  end

  def client(auth_store) do
    AuthStore.get(auth_store) |> client()
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
            auth_or_client :: Auth.t() | AuthStore.name() | Req.Request.t(),
            endpoint :: String.t(),
            opts :: keyword()
          ) ::
            {:ok, Req.Response.t()} | {:error, term()}
    def unquote(method)(auth_or_client, endpoint, opts \\ [])

    def unquote(method)(%Auth{} = auth, endpoint, opts) do
      unquote(method)(client(auth), endpoint, opts)
    end

    def unquote(method)(%Req.Request{} = client, endpoint, opts) do
      {success_code, opts} = Keyword.pop(opts, :success, 200)

      client
      |> Req.unquote(method)([{:url, endpoint} | opts])
      |> handle_response(success_code)
    end

    @doc """
    Make a Twitch API #{method_upcase} request.
    Raises on error or unexpected HTTP status.
    """
    @spec unquote(method!)(
            auth_or_client :: Auth.t() | AuthStore.name() | Req.Request.t(),
            endpoint :: String.t(),
            opts :: keyword()
          ) :: Req.Response.t()
    def unquote(method!)(auth_or_client, endpoint, opts \\ [])

    def unquote(method!)(%Auth{} = auth, endpoint, opts) do
      unquote(method!)(client(auth), endpoint, opts)
    end

    def unquote(method!)(%Req.Request{} = client, endpoint, opts) do
      {success_code, opts} = Keyword.pop(opts, :success, 200)

      client
      |> Req.unquote(method!)([{:url, endpoint} | opts])
      |> handle_response!(success_code)
    end
  end

  @doc """
  GET pages from Twitch API as a `Stream`.

  You can start at a cursor if you pass in `:cursor` as one of the `opts`.
  """
  @spec stream!(
          auth_or_client :: Auth.t() | AuthStore.name() | Req.Request.t(),
          endpoint :: String.t(),
          direction :: :before | :after,
          opts :: keyword()
        ) :: Enumerable.t()
  def stream!(auth_or_client, endpoint, direction, opts \\ []) do
    {starting_cursor, opts} = Keyword.pop(opts, :cursor, nil)

    Stream.resource(
      # start_fun: initial accumulated value, computed lazily.
      fn -> starting_cursor end,

      # next_fun: successive values generated here.
      # This is getting a page of values and sending the data and next cursor.
      fn
        "" ->
          {:halt, nil}

        cursor ->
          params =
            Keyword.get(opts, :params, [])
            |> Keyword.new()
            |> Keyword.merge([{direction, cursor}])

          case get(auth_or_client, endpoint, Keyword.merge(opts, params: params)) do
            {:ok, %{body: %{"data" => data, "pagination" => pagination}}} ->
              cursor = pagination["cursor"] || ""
              {data, cursor}

            {_, error} ->
              raise "Error fetching #{endpoint}: #{inspect(error)}"
          end
      end,

      # after_fun: executes at the end of the enumeration (on success or failure).
      fn acc -> acc end
    )
  end

  @spec handle_response(
          {:ok, Req.Response.t()} | {:error, Req.Response.t() | term()},
          pos_integer()
        ) ::
          {:ok, Req.Response.t()} | {:error, term()}
  defp handle_response(result, expected_status) do
    case result do
      {:ok, %Req.Response{status: ^expected_status} = resp} ->
        {:ok, resp}

      {:ok, %Req.Response{status: _status} = resp} ->
        {:error, resp}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec handle_response!(Req.Response.t(), pos_integer()) :: Req.Response.t()
  defp handle_response!(result, expected_status) do
    case result do
      %{status: ^expected_status} = resp ->
        resp

      %{status: 429, headers: %{"ratelimit-reset" => resets_at}} ->
        raise "rate limited: resets at #{resets_at}"

      %{status: status} ->
        raise "unexpected status #{status}, expected #{expected_status}"
    end
  end
end
