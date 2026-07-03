defmodule SimplyPut.Repo do
  use Ecto.Repo,
    otp_app: :simply_put,
    adapter: Ecto.Adapters.SQLite3
end
