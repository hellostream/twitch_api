defmodule Mix.Tasks.Twitch.Auth do
  @moduledoc """
  A task for getting an OAuth access token from Twitch, using the authorization
  code flow.

  NOTE: To use this, you need to add the local listener to your app's redirect urls:

      http://localhost:42069/oauth/callback

  Where `42069` is the default `--listen-port` value. Change the port to match any
  value you use for this if you specify it yourself.

  ## Usage

      mix twitch.auth [OPTION]

  ## Options

   * `--output` - Specify how we want to output the token. 
     Valid values are: `json`, `.env`, `.envrc`, `stdout`, `clipboard`.
     NOTE: Only `json` and `stdout` are supported currently.

  ## Auth Options

   * `--client-id` - The Twitch client ID for your app. Defaults to the value
     of the `TWITCH_CLIENT_ID` env var if not set.
   * `--client-secret` - The Twitch client secret for your app. Defaults to the
     value of the `TWITCH_CLIENT_SECRET` env var if not set.
   * `--auth-scope` - The Twitch auth scope for your app. A space-separated
     string. Defaults to the value of the `TWITCH_AUTH_SCOPE` env var if not set.
     If the env var is not set, it defaults to the `default_scope` list, which
     should be all `read` scopes except for `whisper` and `stream_key`.
   * `--listen-port` - The port that the temporary web server will listen on.
     Defaults to `42069` if not set.

  ## ENV Vars

   * `TWITCH_CLIENT_ID` - The Twitch client ID for your app.
   * `TWITCH_CLIENT_SECRET` - The Twitch client secret for your app.
   * `TWITCH_AUTH_SCOPE` - The Twitch scopes as a space-separated string.

  """
  use Mix.Task

  @base_url "https://id.twitch.tv/oauth2/authorize"

  @outputs ~w[clipboard .env .envrc json stdout]

  @default_output "json"

  @default_listen_port 42069

  @default_scope_list ~w[
    analytics:read:extensions analytics:read:games bits:read
    channel:read:ads channel:read:charity channel:read:goals
    channel:read:guest_star channel:read:hype_train channel:read:polls
    channel:read:predictions channel:read:redemptions channel:read:subscriptions
    channel:read:vips moderation:read moderator:read:automod_settings
    moderator:read:blocked_terms moderator:read:chat_settings
    moderator:read:chatters moderator:read:followers moderator:read:guest_star
    moderator:read:shield_mode moderator:read:shoutouts user:read:blocked_users
    user:read:broadcast user:read:email user:read:follows user:read:subscriptions
    channel:bot chat:read user:bot user:read:chat
  ]

  @default_scope Enum.join(@default_scope_list, " ")

  @shortdoc "Gets a Twitch access token"

  @doc false
  @impl true
  def run(argv) do
    Logger.configure(level: :error)

    ## Parse args and options.

    {opts, [], []} = OptionParser.parse(argv, switches: [output: :string])

    output = opts[:output] || @default_output

    if output not in @outputs, do: raise("output #{output} not one of #{inspect(@outputs)}")

    client_id = opts[:client_id] || System.fetch_env!("TWITCH_CLIENT_ID")
    client_secret = opts[:client_secret] || System.fetch_env!("TWITCH_CLIENT_SECRET")
    scope = opts[:auth_scope] || System.get_env("TWITCH_AUTH_SCOPE", @default_scope)
    port = opts[:listen_port] || @default_listen_port
    redirect_url = "http://localhost:#{port}/oauth/callback"

    auth = TwitchAPI.Auth.new(client_id, client_secret)

    ## Start services.

    {:ok, _http_client} = Application.ensure_all_started(:req)

    {:ok, webserver} = Bandit.start_link(plug: TwitchAPI.AuthWebServer, port: port)

    {:ok, _authserver} =
      TwitchAPI.AuthServer.start_link(
        auth: auth,
        process: self(),
        output: output,
        redirect_url: redirect_url
      )

    ## Open browser.

    params =
      URI.encode_query(%{
        client_id: client_id,
        redirect_uri: redirect_url,
        response_type: "code",
        scope: scope
      })

    url = "#{@base_url}?#{params}"

    case :os.type() do
      {:unix, _} -> System.cmd("open", [url])
      {:win32, _} -> System.cmd("cmd", ["/c", "start", String.replace(url, "&", "^&")])
    end

    ## Wait for result.

    wait(webserver)
  end

  ## Helpers

  defp wait(webserver) do
    receive do
      :done ->
        Mix.shell().info("Finished successfully")
        Supervisor.stop(webserver, :normal)

      {:failed, reason} ->
        Mix.shell().error(reason)
        Supervisor.stop(webserver, :normal)

      _ ->
        wait(webserver)
    end
  end
end

# ------------------------------------------------------------------------------
# Auth Web Server
# ------------------------------------------------------------------------------
# We need a temporary web server to handle the OAuth callback with the
# authorization code. We then send that code to the `AuthServer` to handle
# the rest.

defmodule TwitchAPI.AuthWebServer do
  @moduledoc false
  @behaviour Plug

  alias TwitchAPI.AuthServer

  import Plug.Conn

  require Logger

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if conn.path_info == ["oauth", "callback"] do
      conn
      |> fetch_query_params()
      |> Map.fetch!(:query_params)
      |> handle_code()
    end

    send_resp(conn, 200, "You can close this window.") |> halt()
  end

  defp handle_code(%{"code" => code} = _params) do
    AuthServer.token_from_code(code)
  end

  defp handle_code(%{"error" => _error} = params) do
    AuthServer.failed("error #{params["error"]}: #{params["error_detail"]}")
  end
end

# ------------------------------------------------------------------------------
# AuthServer (GenServer)
# ------------------------------------------------------------------------------
# This is used for keeping the auth credentials and making the request to
# Twitch API. We need this as a genserver to be able to receive messages from
# the web server and then stopping the main process.

defmodule TwitchAPI.AuthServer do
  @moduledoc false
  use GenServer

  require Logger

  @default_output "json"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def token_from_code(code) do
    GenServer.cast(__MODULE__, {:token_from_code, code})
  end

  def failed(reason) do
    GenServer.cast(__MODULE__, {:failed, reason})
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      auth: Keyword.fetch!(opts, :auth),
      process: Keyword.fetch!(opts, :process),
      redirect_url: Keyword.fetch!(opts, :redirect_url),
      output: Keyword.get(opts, :output) || @default_output
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:token_from_code, code}, state) do
    with(
      {:ok, token} <- fetch_token(state.auth, code, state.redirect_url),
      :ok <- token_output(state.output, token)
    ) do
      send(state.process, :done)
    else
      {:error, reason} ->
        send(state.process, {:failed, reason})
    end

    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:failed, reason}, state) do
    send(state.process, {:failed, reason})
    {:stop, :normal, state}
  end

  ## Helpers

  defp fetch_token(auth, code, redirect_url) do
    case TwitchAPI.Auth.token_get_from_code(auth, code, redirect_url) do
      {:ok, %{status: 200, body: token}} ->
        {:ok, token}

      {_, error} ->
        {:error, "failed to get token #{inspect(error, pretty: true)}"}
    end
  end

  defp token_output("json", token) do
    Logger.debug("[AuthTokenServer] writing json...")

    expires_at = DateTime.utc_now() |> DateTime.add(token["expires_in"], :second)

    json =
      token
      |> Map.put("expires_at", expires_at)
      |> Map.delete("expires_in")
      |> Jason.encode!(pretty: true)

    File.write!(".twitch.json", json)
    Mix.shell().info("Wrote .twitch.json file")
  end

  defp token_output("stdout", token) do
    Mix.shell().info("""
    Access token received:

      TWITCH_ACCESS_TOKEN=#{token["access_token"]}
      TWITCH_REFRESH_TOKEN=#{token["refresh_token"]}
    """)
  end

  defp token_output(output, _token) do
    {:error, "unhandled output type #{output}"}
  end
end
