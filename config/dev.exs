import Config

config :simply_put, SimplyPut.Repo,
  database: Path.expand("../priv/simply_put_dev.db", __DIR__),
  pool_size: 5,
  journal_mode: :wal,
  busy_timeout: 5_000

# Not a real secret -- public demo repo, no sensitive sessions.
config :simply_put, SimplyPutWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  secret_key_base: String.duplicate("simplyputdevonlynotarealsecret1", 3),
  server: true
