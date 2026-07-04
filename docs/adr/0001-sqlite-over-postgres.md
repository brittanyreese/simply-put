# ADR-0001: SQLite, not Postgres

## Status

Accepted

## Context

This repo's one value is a stranger cloning it and getting to green
(`mix deps.get && mix test`) with no credentials and no services to stand
up. It also needs a real background-job story (`Oban`) to demo the batch
pipeline, not a fake one.

## Decision

Use `ecto_sqlite3` plus `Oban.Engines.Lite`. The database is a single
file under `priv/`, created by `mix ecto.setup`. There is nothing else to
install or run.

## Consequences

- A reviewer never needs to install or configure a database server.
- `Oban.Notifiers.PG` (Postgres LISTEN/NOTIFY) is not available; the app
  uses the SQLite-compatible notifier instead.
- Swapping to Postgres later is one dependency and one config block
  (`config/runtime.exs`), not a rewrite. The schema and worker code never
  name SQLite.
- Not a decision to avoid Postgres in production use of this pattern; it's
  scoped to this repo's purpose as a clone-and-run demo.
