defmodule TwitchAPI.Auth.AuthStoreTest do
  use ExUnit.Case, async: false
  use Mimic

  alias TwitchAPI.Auth
  alias TwitchAPI.AuthClient
  alias TwitchAPI.AuthStore

  setup :set_mimic_global

  setup do
    # I don't want to ever accidentally make HTTP requests.
    # So I'm stubbing `Req` and `Req.Request` just to make sure
    # that it errors if I do.
    stub(Req)
    stub(Req.Request)
    :ok
  end

  # ----------------------------------------------------------------------------
  # Unexpired tokens.
  # ----------------------------------------------------------------------------

  @unexpired_token %Auth{
    client_id: "client-id",
    client_secret: "client_secret",
    access_token: "sometoken",
    refresh_token: "sometoken",
    expires_at: DateTime.utc_now() |> DateTime.add(1, :hour)
  }

  defp unexpired_token(_) do
    AuthClient
    |> reject(:token_refresh, 1)
    |> expect(:token_validate, fn _auth ->
      {:ok, %{status: 200}}
    end)

    name = :erlang.phash2(self())

    {:ok, store} =
      AuthStore.start_link(
        auth: @unexpired_token,
        callback_module: TwitchAPI.AuthNoop,
        name: name
      )

    {:ok, store: store, name: name}
  end

  describe "unexpired_token" do
    setup [:unexpired_token]

    test "starts with unexpired token and doesn't refresh", %{store: store} do
      ref = Process.monitor(store)
      state = :sys.get_state(store)
      expires_at = state.auth.expires_at
      refreshes_in = :erlang.read_timer(state.refresh_timer)
      refreshes_at = DateTime.utc_now() |> DateTime.add(refreshes_in, :millisecond)

      assert diff = DateTime.diff(expires_at, refreshes_at, :second)
      # It refreshes 10 minutes before expiry.
      assert diff <= 600
      assert diff > 588

      GenServer.stop(store)
      assert_receive {:DOWN, ^ref, :process, ^store, _}
    end

    test "put/2 and get/1 sets and gets accordingly", %{store: store, name: name} do
      ref = Process.monitor(store)

      auth1 =
        Map.merge(@unexpired_token, %{client_id: "newclient", client_secret: "newsecret"})

      # Testing with name.
      assert :ok = AuthStore.put(name, auth1)
      assert ^auth1 = AuthStore.get(name)

      auth2 =
        Map.merge(@unexpired_token, %{client_id: "newclient", client_secret: "newsecret"})

      # Testing with pid.
      assert :ok = AuthStore.put(store, auth2)
      assert ^auth2 = AuthStore.get(store)

      GenServer.stop(store)
      assert_receive {:DOWN, ^ref, :process, ^store, _}
    end
  end

  # ----------------------------------------------------------------------------
  # Expired tokens.
  # ----------------------------------------------------------------------------

  @expired_token %Auth{
    client_id: "client-id",
    client_secret: "client_secret",
    access_token: "sometoken",
    refresh_token: "sometoken",
    expires_at: DateTime.utc_now() |> DateTime.add(-1, :hour)
  }

  defp expired_token(_) do
    AuthClient
    |> reject(:token_validate, 1)
    |> expect(:token_refresh, fn _auth ->
      body =
        @unexpired_token
        |> Map.from_struct()
        |> Map.new(fn
          {:expires_at, _v} -> {"expires_in", 5000}
          {k, v} -> {to_string(k), v}
        end)

      {:ok, %{status: 200, body: body}}
    end)

    {:ok, store} =
      AuthStore.start_link(auth: @expired_token, callback_module: TwitchAPI.AuthNoop)

    {:ok, store: store}
  end

  describe "expired_token" do
    setup [:expired_token]

    test "starts with unexpired token and doesn't refresh", %{store: store} do
      ref = Process.monitor(store)
      GenServer.stop(store)
      assert_receive {:DOWN, ^ref, :process, ^store, _}
    end
  end
end
