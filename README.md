# TwitchAPI

Twitch API library.

## Installation

The package can be installed by adding `hello_twitch_api` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hello_twitch_api, "~> 0.5.0"}
  ]
end
```

## Mix tasks

### `mix twitch.auth`

You can get an access token and write it to a file or print it.

### `mix twitch.revoke`

You can revoke an access token from CLI, file, or environment variable.
