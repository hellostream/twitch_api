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
  alias TwitchAPI.AuthError

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
          {:auth, Auth.t() | nil}
          | {:name, name()}
          | {:callback_module, module() | nil}
          | {:on_load, auth_store_callback() | nil}
          | {:on_put, auth_store_callback() | nil}
          | {:on_terminate, auth_store_callback() | nil}

  @opaque state :: %{
            auth: Auth.t(),
            name: name(),
            callback_module: module(),
            on_put: auth_store_callback(),
            on_terminate: auth_store_callback(),
            refresh_timer: reference() | nil,
            validate_timer: reference() | nil
          }

  @validate_interval :timer.hours(1)

  @doc """
  Start the auth store.
  """
  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name) || __MODULE__
    Logger.info("[TwitchAPI.AuthStore] starting #{name}...")
    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  @doc """
  Get the auth from the auth store.
  """
  @spec get(name()) :: Auth.t()
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
    name = Keyword.get(opts, :name) || __MODULE__
    callback_module = Keyword.get(opts, :callback_module) || TwitchAPI.AuthNoop
    on_load = Keyword.get(opts, :on_load) || callback_module
    on_put = Keyword.get(opts, :on_put) || callback_module
    on_terminate = Keyword.get(opts, :on_terminate) || callback_module

    auth = Keyword.get(opts, :auth)
    auth = on_callback(:load, on_load, name, auth) || raise "no auth after on_load"

    state = %{
      auth: auth,
      name: name,
      on_put: on_put,
      on_terminate: on_terminate,
      refresh_timer: nil,
      validate_timer: nil
    }

    Process.flag(:trap_exit, true)

    # Check if the access token is expired or expires within 10 minutes.
    if DateTime.diff(auth.expires_at, DateTime.utc_now(), :minute) <= 10 do
      {:ok, %{state | auth: auth}, {:continue, :refresh}}
    else
      refresh_timer = schedule_refresh(auth, nil)
      state = %{state | auth: auth, refresh_timer: refresh_timer}
      {:ok, state, {:continue, :validate}}
    end
  end

  @impl true
  def handle_continue(:refresh, state) do
    auth = refresh(state.auth)
    state = auth_updated(auth, state)
    {:noreply, state}
  end

  def handle_continue(:validate, state) do
    case validate(state.auth) do
      :ok ->
        validate_timer = schedule_validate(nil)
        {:noreply, %{state | validate_timer: validate_timer}}

      :error ->
        {:noreply, state, {:continue, :refresh}}
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
    case validate(state.auth) do
      :ok ->
        schedule_validate(state.validate_timer)
        {:noreply, state}

      :error ->
        auth = refresh(state.auth)
        state = auth_updated(auth, state)
        {:noreply, state}
    end
  end

  def handle_info(:refresh, state) do
    auth = refresh(state.auth)
    state = auth_updated(auth, state)
    {:noreply, state}
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

  # Dispatch the callback fucntion depending on how it is provided (MFA,
  # function, module).
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

  # This should be called everytime the `:auth` is set.
  defp auth_updated(auth, state) do
    auth = on_callback(:put, state.on_put, state.name, auth)
    refresh_timer = schedule_refresh(auth, state.refresh_timer)
    validate_timer = schedule_validate(state.validate_timer)
    %{state | auth: auth, refresh_timer: refresh_timer, validate_timer: validate_timer}
  end

  # Cancel the current `refresh_timer` if it exists and schedule the `:refresh`
  # for 10 minutes before the current token expires.
  defp schedule_refresh(%Auth{expires_at: expires_at}, current_timer) do
    current_timer && Process.cancel_timer(current_timer, async: true, info: false)
    expires_in_ms = DateTime.diff(expires_at, DateTime.utc_now(), :millisecond)
    refresh_in_ms = expires_in_ms - :timer.minutes(10)
    Process.send_after(self(), :refresh, refresh_in_ms)
  end

  # Cancel the current `validate_timer` if it exists and schedule `:validate`
  # according to the interval.
  defp schedule_validate(current_timer) do
    current_timer && Process.cancel_timer(current_timer, async: true, info: false)
    Process.send_after(self(), :validate, @validate_interval)
  end

  defp refresh(auth) do
    case Auth.token_refresh(auth) do
      {:ok, %{status: 200, body: auth_attrs}} ->
        Logger.debug("[TwitchAPI.AuthStore] refreshed token")
        Auth.merge_string_params(auth, auth_attrs)

      {_ok_error, resp} ->
        raise AuthError, "failed to refresh token: #{inspect(resp, pretty: true)}"
    end
  end

  defp validate(auth) do
    case Auth.token_validate(auth) do
      {:ok, %{status: 200}} ->
        Logger.debug("[TwitchAPI.AuthStore] validated token")
        :ok

      {_ok_error, _resp} ->
        Logger.debug("[TwitchAPI.AuthStore] token is not valid")
        :error
    end
  end
end
