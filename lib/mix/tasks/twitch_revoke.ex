defmodule Mix.Tasks.Twitch.Revoke do
  @moduledoc """
  Revoke an auth token from a file or environment variable.

  ## Usage

      mix twitch.revoke [TOKEN] [OPTION]

  ## Options

   * `--env` The name of the environment variable with the token to revoke.
     Defaults to `TWITCH_ACCESS_TOKEN`.
   * `--json` The name of the JSON file that has the auth token to revoke.
     Defaults to `.twitch.json`.
   * `--client_id` - The Client ID of app the token is for.
     Defaults to fetching the value of `TWITCH_CLIENT_ID` environment variable.

  """
  use Mix.Task

  alias TwitchAPI.Auth

  @default_json ".twitch.json"

  @default_env "TWITCH_ACCESS_TOKEN"

  @shortdoc "Revoke an auth token from env var or file"

  @impl true
  def run(argv) do
    {opts, args} =
      case OptionParser.parse(argv, switches: []) do
        {opts, args, []} -> {Map.new(opts), args}
        {_opts, _arg, _rest} -> raise "requires a token or a single option"
      end

    token =
      case {opts, args} do
        {_, [token]} -> token
        {%{env: env}, _} -> token_from_env(env)
        {%{json: json}, _} -> token_from_json(json)
        _ -> token_from_env(true)
      end

    client_id =
      case opts do
        %{client_id: client_id} -> client_id
        _ -> System.fetch_env!("TWITCH_CLIENT_ID")
      end

    auth =
      client_id
      |> Auth.new()
      |> Auth.put_access_token(token)

    {:ok, _} = Application.ensure_all_started(:req)

    case Auth.token_revoke(auth) do
      {:ok, %{status: 200}} ->
        Mix.shell().info("Token revoked")

      {_, error} ->
        Mix.shell().error("Failed to revoke token:\n#{inspect(error, pretty: true)}")
    end
  end

  ## Helpers

  defp token_from_json(true), do: token_from_json(@default_json)

  defp token_from_json(file) do
    file
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("access_token")
  end

  defp token_from_env(true), do: token_from_env(@default_env)

  defp token_from_env(env) do
    System.fetch_env!(env)
  end
end
