defmodule TwitchAPI.MixProject do
  use Mix.Project

  @repo_url "https://github.com/hellostream/twitch_api"

  def project do
    [
      app: :hello_twitch_api,
      version: "0.4.14",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @repo_url,
      homepage_url: @repo_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.4.11"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:bandit, "~> 1.0", runtime: false}
    ]
  end

  defp description do
    "Twitch API library"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @repo_url}
    ]
  end
end
