import Config

config :simply_put, SimplyPut.Repo,
  database: Path.expand("../priv/simply_put_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5,
  log: false

config :simply_put, Oban, testing: :manual

config :simply_put, SimplyPutWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("simplyputtestonlynotarealsecret", 3),
  server: false

config :logger, level: :warning
