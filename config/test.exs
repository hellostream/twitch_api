import Config

config :logger, level: :error

config :hello_twitch_api, TwitchAPI.AuthStore, validate_interval: 500
