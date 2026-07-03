import Config

config :simply_put, ecto_repos: [SimplyPut.Repo]

import_config "#{config_env()}.exs"
