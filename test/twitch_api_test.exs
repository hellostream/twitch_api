defmodule TwitchAPITest do
  use ExUnit.Case
  doctest TwitchAPI

  test "greets the world" do
    assert TwitchAPI.hello() == :world
  end
end
