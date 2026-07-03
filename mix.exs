defmodule SimplyPut.MixProject do
  use Mix.Project

  def project do
    [
      app: :simply_put,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {SimplyPut.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.14"},
      {:jason, "~> 1.4"},
      {:ecto_sqlite3, "~> 0.24"},
      {:nimble_csv, "~> 1.3"},
      {:oban, "~> 2.23"},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.2"},
      {:bandit, "~> 1.12"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:elixir_make, "~> 0.9 or ~> 0.10", override: true}
    ]
  end

  defp aliases do
    [
      quality: ["format --check-formatted", "credo --strict", "compile --warnings-as-errors"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
