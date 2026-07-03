import Config

config :simply_put, SimplyPut.Repo,
  database: Path.expand("../priv/simply_put_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5,
  log: false
