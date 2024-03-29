defmodule TwitchAPI.TempWebServer do
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

    send_resp(conn, 200, "OKAY MAN") |> halt()
  end

  defp handle_code(%{"code" => code} = _params) do
    TwitchAPI.AuthTokenServer.get_token_from_code(code)
  end

  defp handle_code(%{"error" => error} = params) do
    Logger.error("[TempWebServer] error #{error}: #{params["error_description"]}")
  end
end

defmodule TwitchAPI.AuthTokenServer do
  use GenServer

  require Logger

  @default_output "json"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_token_from_code(code) do
    GenServer.cast(__MODULE__, {:token_from_code, code})
  end

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
    result = TwitchAPI.Auth.token_get_from_code(state.auth, code, state.redirect_url)

    case result do
      {:ok, %{body: token}} -> token_output(state.output, token)
      {:error, error} -> raise "Failed to get token #{inspect(error)}"
    end

    send(state.process, :done)

    {:stop, :normal, state}
  end

  defp token_output("json", token) do
    Logger.debug("[AuthTokenServer] writing json...")

    expires_at = DateTime.utc_now() |> DateTime.add(token["expires_in"], :second)

    json =
      token
      |> Map.put("expires_at", expires_at)
      |> Map.delete("expires_in")
      |> Jason.encode!(pretty: true)

    # write json
    "../../../.twitch.json"
    |> Path.expand(__DIR__)
    |> File.write!(json)
  end

  defp token_output(output, _token) do
    raise "unhandled output type #{output}"
  end
end

defmodule Mix.Tasks.Auth.Token do
  use Mix.Task

  @base_url "https://id.twitch.tv/oauth2/authorize"
  @port 42069

  @impl true
  def run(argv) do
    # mix auth.token --output .env | .envrc | json | stdio | clipboard
    {opts, [], []} = OptionParser.parse(argv, strict: [output: :string])

    Application.ensure_all_started(:req)

    # Get required variables...
    # TODO: Check args first.
    client_id = System.fetch_env!("TWITCH_CLIENT_ID")
    client_secret = System.fetch_env!("TWITCH_CLIENT_SECRET")
    scope = System.fetch_env!("TWITCH_AUTH_SCOPE")
    redirect_url = "http://localhost:#{@port}/oauth/callback"

    auth = TwitchAPI.Auth.new(client_id, client_secret)

    # Temporary webserver for redirect back.

    {:ok, bandit_pid} = Bandit.start_link(plug: TwitchAPI.TempWebServer, port: @port)

    # Open browser to authorize URL.

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

    # GenServer for dealing with state...

    {:ok, _token_pid} =
      TwitchAPI.AuthTokenServer.start_link(
        auth: auth,
        process: self(),
        output: opts[:output],
        redirect_url: redirect_url
      )

    wait(bandit_pid)
  end

  defp wait(bandit_pid) do
    receive do
      :done -> Supervisor.stop(bandit_pid, :normal)
      _ -> wait(bandit_pid)
    end
  end
end
