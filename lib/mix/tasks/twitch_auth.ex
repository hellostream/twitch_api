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
     Valid values are: `json`, `priv`, `.env`, `.envrc`, `stdout`, `clipboard`.
     NOTE: Only `priv`, `json`, and `stdout` are supported currently.
   * `--listen-port` - The port that the temporary web server will listen on.
     Defaults to `42069` if not set.
   * `--listen-timeout` - The time in ms that the server waits for a the twitch
     redirect with the authorization code. Defaults to `300_000` if not set.

  ## Auth Options

   * `--client-id` - The Twitch client ID for your app. Defaults to the value
     of the `TWITCH_CLIENT_ID` env var if not set.
   * `--client-secret` - The Twitch client secret for your app. Defaults to the
     value of the `TWITCH_CLIENT_SECRET` env var if not set.
   * `--auth-scope` - The Twitch auth scope for your app. A space-separated
     string. Defaults to the value of the `TWITCH_AUTH_SCOPE` env var if not set.
     If the env var is not set, it defaults to the `default_scope` list, which
     should be all `read` scopes except for `whisper` and `stream_key`.

  ## ENV Vars

   * `TWITCH_CLIENT_ID` - The Twitch client ID for your app.
   * `TWITCH_CLIENT_SECRET` - The Twitch client secret for your app.
   * `TWITCH_AUTH_SCOPE` - The Twitch scopes as a space-separated string.

  """
  use Mix.Task

  @base_url "https://id.twitch.tv/oauth2/authorize"

  @outputs ~w[.env .envrc clipboard json priv stdout]

  @default_output "priv"

  @default_listen_port 42069

  @default_listen_timeout 300_000

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
    scope = opts[:auth_scope] || System.fetch_env!("TWITCH_AUTH_SCOPE")
    port = opts[:listen_port] || @default_listen_port
    timeout = opts[:listen_timeout] || @default_listen_timeout
    redirect_url = "http://localhost:#{port}/oauth/callback"

    auth = TwitchAPI.Auth.new(client_id, client_secret)

    ## Start services.

    {:ok, _http_client} = Application.ensure_all_started(:req)

    {:ok, _webserver} =
      Bandit.start_link(
        plug: {TwitchAPI.AuthWebServer, process: self()},
        port: port
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

    ## Wait for the code result, and then fetch the token, and write it to output.

    with(
      {:ok, code} <- wait_for_code(timeout),
      {:ok, token} <- fetch_token(auth, code, redirect_url),
      auth <- TwitchAPI.Auth.merge_string_params(auth, token),
      :ok <- token_output(output, auth)
    ) do
      Mix.shell().info("Finished successfully")
    else
      {:error, reason} ->
        Mix.shell().error(reason)
    end
  end

  ## Helpers

  defp wait_for_code(timeout) do
    receive do
      {:code, code} -> {:ok, code}
      {:failed, reason} -> {:error, reason}
      _ -> wait_for_code(timeout)
    after
      timeout ->
        {:error, "No response after #{div(timeout, 1000)} seconds"}
    end
  end

  defp fetch_token(auth, code, redirect_url) do
    case TwitchAPI.AuthClient.token_get_from_code(auth, code, redirect_url) do
      {:ok, %{status: 200, body: token}} ->
        {:ok, token}

      {:ok, %{body: body}} ->
        {:error, "Token fetch error:\n#{inspect(body, pretty: true)}"}

      {_, error} ->
        {:error, "Token fetch error:\n#{inspect(error, pretty: true)}"}
    end
  end

  ## Write the token output

  defp token_output("json", auth) do
    json = Jason.encode!(auth, pretty: true)
    File.write!(".twitch.json", json)
    Mix.shell().info("Wrote .twitch.json file")
  end

  defp token_output("priv", auth) do
    filename = "auth/.twitch-Elixir.TwitchAPI.AuthStore"

    :hello_twitch_api
    |> :code.priv_dir()
    |> Path.join(filename)
    |> File.write!(:erlang.term_to_binary(auth))
    |> dbg()

    Mix.shell().info("Wrote #{filename}")
  end

  defp token_output("stdout", auth) do
    Mix.shell().info("""
    Access token received:

      TWITCH_ACCESS_TOKEN=#{auth.access_token}
      TWITCH_REFRESH_TOKEN=#{auth.refresh_token}

    Expires at: #{auth.expires_at}
    """)
  end

  defp token_output(output, _auth) do
    {:error, "unhandled output type #{output}"}
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

  alias Plug.Conn

  require Logger

  @impl true
  def init(opts), do: Keyword.fetch!(opts, :process)

  @impl true
  def call(conn, process) do
    if conn.path_info == ["oauth", "callback"] do
      conn
      |> Conn.fetch_query_params()
      |> tap(&handle_code(&1.query_params, process))
      |> Conn.send_resp(200, "You can close this window")
      |> Conn.halt()
    else
      conn
      |> Conn.send_resp(404, "Not found")
      |> Conn.halt()
    end
  end

  defp handle_code(%{"code" => code}, process) do
    send(process, {:code, code})
  end

  defp handle_code(%{"error" => error, "error_detail" => detail}, process) do
    send(process, {:failed, "error #{error}: #{detail}"})
  end
end
