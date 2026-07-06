import Config

config :simply_put, ecto_repos: [SimplyPut.Repo]

config :simply_put, Oban,
  engine: Oban.Engines.Lite,
  notifier: Oban.Notifiers.PG,
  repo: SimplyPut.Repo,
  queues: [rewrites: 5],
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}]

config :simply_put, SimplyPutWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: SimplyPut.PubSub,
  live_view: [signing_salt: "sp_live_view_salt"]

config :phoenix, :json_library, Jason

config :nx, default_backend: EXLA.Backend

import_config "#{config_env()}.exs"
