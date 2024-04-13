defmodule TwitchAPI.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: TwitchAPI.AuthRegistry}
    ]

    opts = [strategy: :one_for_one, name: TwitchAPI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
