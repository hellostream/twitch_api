defmodule TwitchAPI.AuthFile do
  @moduledoc """
  Some functions to read and write Twitch Auth from and to a file.
  """
  @behaviour TwitchAPI.AuthCallbacks

  require Logger

  @base_filename "auth/.twitch-"

  @impl true
  def load(name, auth) do
    case try_load_files(name, auth) do
      {:ok, %TwitchAPI.Auth{} = auth} ->
        Logger.debug("[TwitchAPI.AuthFile] loaded auth from file")
        auth

      {:ok, nil} ->
        Logger.error("[TwitchAPI.AuthFile] error reading auth, file is empty")
        auth

      {:error, posix} ->
        Logger.error("[TwitchAPI.AuthFile] error reading auth: #{posix}")
        auth
    end
  end

  @impl true
  def put(name, auth) do
    result =
      name
      |> filename()
      |> File.write(:erlang.term_to_binary(auth))

    with {:error, posix} <- result do
      Logger.error("[TwitchAPI.AuthFile] error writing auth: #{posix}")
    end

    auth
  end

  @impl true
  def terminate(name, auth) do
    put(name, auth)
  end

  defp filename(name) do
    :code.priv_dir(:hello_twitch_api) |> Path.join("#{@base_filename}#{name}")
  end

  defp filename_json do
    :code.priv_dir(:hello_twitch_api) |> Path.join("auth/.twitch.json")
  end

  defp try_load_files(name, auth) do
    case File.read(filename(name)) do
      {:ok, data} ->
        {:ok, :erlang.binary_to_term(data)}

      {:error, posix} ->
        case File.read(filename(TwitchAPI.AuthStore)) do
          {:ok, data} ->
            {:ok, :erlang.binary_to_term(data)}

          {:error, _posix} ->
            case File.read(filename_json()) do
              {:ok, data} ->
                access_token = Jason.decode!(data)
                auth = TwitchAPI.Auth.merge_string_params(auth, access_token)
                {:ok, auth}

              {:error, _posix} ->
                {:error, posix}
            end
        end
    end
  end
end
