defmodule Mix.Tasks.SimplyPut.ImportCorpus do
  @shortdoc "Import a corpus CSV into corpus_items"
  @moduledoc """
  Usage: mix simply_put.import_corpus <source> <path>

  Only `med_easi` is implemented for Phase 1. Starts only `Ecto.Repo`, not
  the full application (Iron Law #12: never `app.start` from a mix task,
  it would boot Oban consuming and the endpoint port).
  """

  use Mix.Task

  alias SimplyPut.Corpus.Import

  @impl Mix.Task
  def run([source, path]) do
    Mix.Task.run("app.config")
    Application.ensure_all_started(:ecto_sql)
    SimplyPut.Repo.start_link()

    case source do
      "med_easi" ->
        case Import.import_med_easi(path) do
          {:ok, count} -> Mix.shell().info("Imported #{count} Med-EASi corpus items.")
          {:error, reason} -> Mix.raise("Import failed: #{inspect(reason)}")
        end

      other ->
        Mix.raise("Unknown corpus source: #{inspect(other)}. Supported: med_easi")
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix simply_put.import_corpus <source> <path>")
  end
end
