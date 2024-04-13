defmodule TwitchAPI.AuthStore do
  @moduledoc """
  Storage for Twitch Auth.

  ### The callback options

  These can be useful for things like loading and saving the auth tokens to a
  more persisten store (or file) between app restarts or deploys.

  The callback options accept either a module that implements the
  `TwitchAPI.AuthCallbacks` behaviour, a function, or a tuple in the standard
  format of `{Module, :function, [args]}` (MFA).

  If you use an MFA the first two args passed to you function will still always
  be `name` and `auth`, and the rest will be the ones you pass in `[args]`.

  They default to `TwitchAPI.AuthNoop` unless you supply the `:callback_module`
  option, this will be used instead.

   * `:on_load` - Called after auth store init and before token is validated.
   * `:on_put` - Called when `t:TwitchAPI.Auth.t/0` is added to auth store or
     token is refreshed.
   * `:on_terminate` - Called when the `TwitchAPI.AuthStore` terminates.

  """
  use GenServer

  alias TwitchAPI.Auth

  require Logger

  @typedoc """
  The `name` argument is the name used to register the auth store in the
  `Registry`, and is useful for distinguishing between different auth stores
  if you have many.
  """
  @type name :: term()

  @typedoc """
  See the `TwitchAPI.AuthStore` module docs for an explanation.
  """
  @type auth_store_callback ::
          {module(), function :: atom(), args :: [term()]}
          | (name(), Auth.t() -> Auth.t())
          | module()

  @type option ::
          {:auth, Auth.t()}
          | {:name, name()}
          | {:callback_module, module() | nil}
          | {:on_load, auth_store_callback() | nil}
          | {:on_put, auth_store_callback() | nil}
          | {:on_terminate, auth_store_callback() | nil}

  @validate_interval :timer.hours(1)

  @doc """
  Start the auth store.
  """
  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name) || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  @doc """
  Get the auth from the auth store.
  """
  @spec get(name()) :: Auth.t() | nil
  def get(name) when is_atom(name) or is_pid(name) do
    GenServer.call(name, :get)
  end

  @doc """
  Put the auth in the auth store.
  """
  @spec put(name(), Auth.t()) :: :ok
  def put(name, %Auth{} = auth) when is_atom(name) or is_pid(name) do
    GenServer.cast(via(name), {:put, name, auth})
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    auth = Keyword.get(opts, :auth)
    name = Keyword.get(opts, :name) || __MODULE__
    callback_module = Keyword.get(opts, :callback_module) || TwitchAPI.AuthNoop
    on_load = Keyword.get(opts, :on_load) || callback_module
    on_put = Keyword.get(opts, :on_put) || callback_module
    on_terminate = Keyword.get(opts, :on_terminate) || callback_module

    state = %{
      auth: auth,
      name: name,
      on_load: on_load,
      on_put: on_put,
      on_terminate: on_terminate
    }

    Process.flag(:trap_exit, true)

    {:ok, state, {:continue, :load_token}}
  end

  @impl GenServer
  def handle_continue(:load_token, state) do
    case on_callback(:load, state.on_load, state.name, state.auth) do
      nil -> {:noreply, state}
      auth -> {:noreply, %{state | auth: auth}, {:continue, :validate}}
    end
  end

  def handle_continue(:validate, state) do
    case validate_or_refresh(state.auth) do
      {:ok, auth} ->
        state = auth_updated(auth, state)
        {:noreply, state}

      :error ->
        {:stop, {:shutdown, :invalid_token}, state}
    end
  end

  @impl GenServer
  def handle_call(:get, _from, state) do
    {:reply, state.auth, state}
  end

  @impl GenServer
  def handle_call({:put, _name, auth}, _from, state) do
    state = auth_updated(auth, state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:validate, state) do
    case validate_or_refresh(state.auth) do
      {:ok, auth} ->
        state = auth_updated(auth, state)
        {:noreply, state}

      :error ->
        {:stop, {:shutdown, :invalid_token}, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    on_callback(:terminate, state.on_terminate, state.name, state.auth)
  end

  # ----------------------------------------------------------------------------
  # Private API
  # ----------------------------------------------------------------------------

  defp via(name) do
    {:via, Registry, {TwitchAPI.AuthRegistry, name}}
  end

  defp schedule_validate do
    Process.send_after(self(), :validate, @validate_interval)
  end

  defp schedule_refresh(%Auth{expires_at: expires_at}) do
    expires_in_ms = DateTime.diff(expires_at, DateTime.utc_now(), :millisecond)
    Process.send_after(self(), :refresh, expires_in_ms)
  end

  defp auth_updated(auth, state) do
    schedule_validate()
    schedule_refresh(state.auth)
    auth = on_callback(:put, state.on_put, state.name, auth)
    %{state | auth: auth}
  end

  defp on_callback(callback_name, callback, name, auth) do
    case callback do
      module when is_atom(module) ->
        apply(module, callback_name, [name, auth])

      fun when is_function(fun) ->
        fun.(name, auth)

      {mod, fun, args} ->
        apply(mod, fun, [name, auth | args])

      other ->
        Logger.error("[TwitchAPI.AuthStore] invalid callback: #{inspect(other)}")
        auth
    end
  end

  defp validate_or_refresh(auth) do
    with(
      :error <- validate(auth),
      {:ok, auth} <- refresh(auth)
    ) do
      {:ok, auth}
    end
  end

  defp validate(auth) do
    case Auth.token_validate(auth) do
      {:ok, %{status: 200}} -> {:ok, auth}
      {_ok_error, _resp} -> :error
    end
  end

  defp refresh(auth) do
    case Auth.token_refresh(auth) do
      {:ok, %{status: 200, body: auth_attrs}} ->
        auth = Auth.merge_string_params(auth, auth_attrs)
        {:ok, auth}

      {_ok_error, resp} ->
        Logger.error("[TwitchAPI.AuthStore] Failed to refresh token: #{inspect(resp)}")
        :error
    end
  end
end
