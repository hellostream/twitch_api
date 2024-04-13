defmodule TwitchAPI.AuthFile do
  @moduledoc """
  Some functions to read and write Twitch Auth from and to a file.
  """
  @behaviour TwitchAPI.AuthCallbacks

  require Logger

  @base_filename "auth/.twitch-"

  @impl true
  def load(name, auth) do
    case filename(name) |> File.read() do
      {:ok, data} ->
        :erlang.binary_to_term(data)

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

    case result do
      :ok ->
        auth

      {:error, posix} ->
        Logger.error("[TwitchAPI.AuthFile] error reading auth: #{posix}")
        auth
    end
  end

  @impl true
  def terminate(name, auth) do
    put(name, auth)
  end

  defp filename(name) do
    :code.priv_dir(:hello_twitch_api) |> Path.join("#{@base_filename}#{name}")
  end
end
