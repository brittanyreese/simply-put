import Config

config :simply_put, ecto_repos: [SimplyPut.Repo]

config :simply_put, Oban,
  engine: Oban.Engines.Lite,
  notifier: Oban.Notifiers.PG,
  repo: SimplyPut.Repo,
  queues: [rewrites: 5],
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}]

import_config "#{config_env()}.exs"
