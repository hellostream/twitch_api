defmodule TwitchAPI.AuthStore do
  @moduledoc """
  Storage for Twitch Auth.
  """
  use GenServer

  alias TwitchAPI.Auth

  require Logger

  @type option :: {:auth, Auth.t()} | {:name, GenServer.name()}

  @validate_interval 60 * 60 * 1000

  @base_filename ".auth/.twitch-"

  @doc """
  Start the auth store.
  """
  @spec start_link([option]) :: Agent.on_start()
  def start_link(opts) do
    %Auth{} = auth = Keyword.fetch!(opts, :auth)
    name = Keyword.get(opts, :name) || __MODULE__
    GenServer.start_link(__MODULE__, auth, name: name)
  end

  @doc """
  Get the auth from the auth store.
  """
  @spec get(name :: atom() | pid()) :: Auth.t() | nil
  def get(name) when is_atom(name) or is_pid(name) do
    case Registry.lookup(TwitchAPI.Registry, name) do
      [{_key, auth}] -> auth
      [] -> nil
    end
  end

  @doc """
  Put the auth in the auth store.
  """
  @spec put(name :: atom() | pid(), Auth.t()) :: :ok
  def put(name, %Auth{} = auth) when is_atom(name) or is_pid(name) do
    GenServer.call(name, {:put, name, auth})
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(auth) do
    Process.flag(:trap_exit, true)

    state = %{
      auth: auth,
      timer_ref: nil
    }

    {:ok, state, {:continue, :load_token}}
  end

  @impl GenServer
  def handle_continue(:load_token, state) do
    auth =
      state.name
      |> read_from_file(state.auth)
      |> Map.merge(Map.take(state.auth, [:client_id, :client_secret]))

    Registry.register(TwitchAPI.Registry, state.name, auth)

    {:noreply, %{state | auth: auth}, {:continue, :validate}}
  end

  def handle_continue(:validate, state) do
    case validate_or_refresh(state.name, state.auth) do
      {:ok, auth} ->
        timer_ref = schedule_validate()
        {:noreply, %{state | auth: auth, timer_ref: timer_ref}}

      :error ->
        {:stop, {:shutdown, :invalid_token}, state}
    end
  end

  @impl GenServer
  def handle_call({:put, name, auth}, _from, state) do
    with {:error, {:already_registered, _}} <- Registry.register(TwitchAPI.Registry, name, auth) do
      Registry.update_value(TwitchAPI.Registry, name, fn _ -> auth end)
    end

    write_to_file(name, auth)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:validate, state) do
    case validate_or_refresh(state.name, state.auth) do
      {:ok, auth} ->
        timer_ref = schedule_validate()
        {:noreply, %{state | auth: auth, timer_ref: timer_ref}}

      :error ->
        {:stop, {:shutdown, :invalid_token}, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    write_to_file(state.name, state.auth)
  end

  # ----------------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------------

  defp filename(name) do
    :code.priv_dir(:twitch_api) |> Path.join("#{@base_filename}#{name}")
  end

  defp read_from_file(name, auth_default) do
    case filename(name) |> File.read() do
      {:ok, file} ->
        :erlang.binary_to_term(file)

      {:error, :enoent} ->
        write_to_file(name, auth_default)
        auth_default

      {:error, _posix} ->
        auth_default
    end
  end

  defp write_to_file(name, auth) do
    name
    |> filename()
    |> File.write(:erlang.term_to_binary(auth))
  end

  defp schedule_validate do
    Process.send_after(self(), :validate, @validate_interval)
  end

  defp validate_or_refresh(name, auth) do
    with(
      :error <- validate(auth),
      {:ok, auth} <- refresh(auth)
    ) do
      write_to_file(name, auth)
      {:ok, auth}
    end
  end

  defp validate(auth) do
    case TwitchAPI.Auth.token_validate(auth) do
      {:ok, %{status: 200}} -> {:ok, auth}
      {_ok_error, _resp} -> :error
    end
  end

  defp refresh(auth) do
    case TwitchAPI.Auth.token_refresh(auth) do
      {:ok, %{status: 200, body: auth_attrs}} ->
        auth = TwitchAPI.Auth.merge_string_params(auth, auth_attrs)
        {:ok, auth}

      {_ok_error, resp} ->
        Logger.error("[TwitchAPI.AuthStore] Failed to refresh token: #{inspect(resp)}")
        :error
    end
  end
end
