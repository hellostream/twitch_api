defmodule Mix.Tasks.Auth.Token do
  @moduledoc """
  A task for getting an OAuth access token from Twitch, using the authorization
  code flow.

  ## Usage

      mix auth.token --output json

  ## Options

   * `--output` - Specify how we want to output the token. 
     Valid values are: `json`, `.env`, `.envrc`, `stdio`, `clipboard`.
     NOTE: Only `json` is supported currently.

  ## ENV Vars

   * `TWITCH_CLIENT_ID` - The Twitch client ID for your app.
   * `TWITCH_CLIENT_SECRET` - The Twitch client secret for your app.
   * `TWITCH_AUTH_SCOPE` - The Twitch scopes as a space-separated string.
   * `TWITCH_AUTH_PORT` - The port that the temp web server will listen on.
     Defaults to `42069`.

  """
  use Mix.Task

  @base_url "https://id.twitch.tv/oauth2/authorize"

  @shortdoc "Gets an access token from Twitch and writes it to `:output`"
  @impl true
  def run(argv) do
    # mix auth.token --output .env | .envrc | json | stdio | clipboard
    {opts, [], []} = OptionParser.parse(argv, strict: [output: :string])

    Application.ensure_all_started(:req)

    # TODO: Check args first.
    client_id = System.fetch_env!("TWITCH_CLIENT_ID")
    client_secret = System.fetch_env!("TWITCH_CLIENT_SECRET")
    scope = System.fetch_env!("TWITCH_AUTH_SCOPE")
    port = System.get_env("TWITCH_AUTH_PORT", "42069") |> String.to_integer()
    redirect_url = "http://localhost:#{port}/oauth/callback"

    auth = TwitchAPI.Auth.new(client_id, client_secret)

    {:ok, bandit_pid} = Bandit.start_link(plug: TwitchAPI.AuthWebServer, port: port)

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
      {:win32, _} -> System.cmd("cmd", ["/c", "start", url])
    end

    {:ok, _token_pid} =
      TwitchAPI.AuthServer.start_link(
        auth: auth,
        process: self(),
        output: opts[:output],
        redirect_url: redirect_url
      )

    wait(bandit_pid)
  end

  ## Helpers

  defp wait(bandit_pid) do
    receive do
      :done ->
        Mix.shell().info("Finished successfully")
        Supervisor.stop(bandit_pid, :normal)

      {:failed, reason} ->
        Mix.shell().error(reason)
        Supervisor.stop(bandit_pid, :normal)

      _ ->
        wait(bandit_pid)
    end
  end
end

# ------------------------------------------------------------------------------
# Auth Web Server
# ------------------------------------------------------------------------------
# We need a temporary web server to handle the OAuth callback with the
# authorization code. We then send that code to the `AuthTokenServer` to handle
# the rest.

defmodule TwitchAPI.AuthWebServer do
  @moduledoc false
  @behaviour Plug

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
    TwitchAPI.AuthServer.get_token_from_code(code)
  end

  defp handle_code(%{"error" => _error} = params) do
    TwitchAPI.AuthServer.failed("error #{params["error"]}: #{params["error_detail"]}")
  end
end

# ------------------------------------------------------------------------------
# Auth GenServer
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

  def get_token_from_code(code) do
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

  def fetch_token(auth, code, redirect_url) do
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
  end

  defp token_output(output, _token) do
    {:error, "unhandled output type #{output}"}
  end
end
