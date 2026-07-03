import Config

config :simply_put, SimplyPut.Repo,
  database: Path.expand("../priv/simply_put_dev.db", __DIR__),
  pool_size: 5
